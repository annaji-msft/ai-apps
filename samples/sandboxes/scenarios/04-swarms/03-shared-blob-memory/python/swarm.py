"""Swarm with shared-blob memory — MI inception + a durable scratchpad.

Same orchestrator-spawns-workers shape as
``../../01-mi-inception/python/swarm.py``, plus an Azure Blob
container that every sandbox in the swarm reads and writes through
its managed identity:

  1. Host provisions:
       * orchestrator sandbox group (SystemAssigned MI)
       * worker       sandbox group (SystemAssigned MI)
       * storage account + container "shared-memory"
  2. Host grants:
       * orchestrator MI ← Container Apps SandboxGroup Data Owner on worker group
       * orchestrator MI ← Storage Blob Data Contributor on the container
       * worker        MI ← Storage Blob Data Contributor on the container
  3. Orchestrator sandbox boots, gets the SDK + the inner script.
  4. Orchestrator fans out N workers in the worker group via MI.
  5. Each worker writes per-checkpoint progress JSON to the container.
  6. Orchestrator never reads worker stdout; it learns the swarm
     state by listing + downloading blobs.

Reads configuration from ``samples/.env`` (written by the baseline
setup in ``samples/sandboxes/setup``).
"""

from __future__ import annotations

import json
import os
import sys
import textwrap
import time
import urllib.request
import uuid
from pathlib import Path

from azure.core.exceptions import HttpResponseError
from azure.identity import DefaultAzureCredential
from azure.mgmt.authorization import AuthorizationManagementClient
from azure.mgmt.storage import StorageManagementClient
from azure.storage.blob import BlobServiceClient
from azure.containerapps.sandbox import (
    SandboxGroupClient,
    SandboxGroupManagementClient,
    endpoint_for_region,
)

SDK_WHEEL_URL = (
    "https://github.com/microsoft/azure-container-apps/releases/download/"
    "python-sdk-v0.1.0b1-early-access/"
    "azure_containerapps_sandbox-0.1.0b1-py3-none-any.whl"
)
ORCH_DISK = "python-3.14"
WORKERS = 4
DARTS_PER_WORKER = 1_000_000
CHECKPOINT_EVERY = 200_000
CONTAINER_NAME = "shared-memory"
SANDBOX_DATA_OWNER = "Container Apps SandboxGroup Data Owner"
BLOB_DATA_CONTRIBUTOR = "Storage Blob Data Contributor"
RBAC_PROPAGATION_SECONDS = 90  # blob data-plane RBAC needs longer than ARM control-plane


# ---------------------------------------------------------------------------
# Runs INSIDE the orchestrator sandbox. Auths to the worker sandbox group
# AND to blob via ManagedIdentityCredential; fans out N workers; in each
# worker, computes Pi in batches, writing per-checkpoint state to the
# shared container; then lists/reads the result blobs and prints a single
# RESULT={json} line for the host.
# ---------------------------------------------------------------------------
SPAWN_WORKERS_SCRIPT = textwrap.dedent('''\
    from __future__ import annotations

    import asyncio
    import json
    import os
    import textwrap

    from azure.identity.aio import ManagedIdentityCredential
    from azure.storage.blob.aio import BlobServiceClient
    from azure.containerapps.sandbox.aio import SandboxGroupClient
    from azure.containerapps.sandbox import endpoint_for_region

    SUBSCRIPTION   = os.environ["AZURE_SUBSCRIPTION_ID"]
    RG             = os.environ["ACA_RESOURCE_GROUP"]
    WORKER_GROUP   = os.environ["WORKER_SANDBOX_GROUP"]
    REGION         = os.environ["ACA_SANDBOXGROUP_REGION"]
    STORAGE_ACCT   = os.environ["STORAGE_ACCOUNT"]
    CONTAINER      = os.environ["CONTAINER_NAME"]
    RUN_ID         = os.environ["RUN_ID"]
    WORKERS        = int(os.environ["WORKERS"])
    DARTS          = int(os.environ["DARTS_PER_WORKER"])
    CHECKPOINT     = int(os.environ["CHECKPOINT_EVERY"])

    # Tiny Pi worker that streams a checkpoint blob every CHECKPOINT darts.
    # The whole script is run from the worker sandbox via `python3 -c` and
    # uses ManagedIdentityCredential — same MI the orchestrator used to
    # spawn the worker, but here scoped to one container only.
    WORKER_PY = textwrap.dedent("""\\
        import asyncio, json, os, random, sys
        from azure.identity.aio import ManagedIdentityCredential
        from azure.storage.blob.aio import BlobServiceClient

        async def main():
            i          = int(sys.argv[1])
            total      = int(sys.argv[2])
            checkpoint = int(sys.argv[3])
            account    = os.environ["STORAGE_ACCOUNT"]
            container  = os.environ["CONTAINER_NAME"]
            run_id     = os.environ["RUN_ID"]
            blob_name  = f"{run_id}/worker-{i}.json"

            cred = ManagedIdentityCredential()
            svc = BlobServiceClient(f"https://{account}.blob.core.windows.net", credential=cred)
            c = svc.get_container_client(container)

            inside = 0
            checkpoints = []
            try:
                for k in range(1, total + 1):
                    x = random.random(); y = random.random()
                    if x*x + y*y < 1.0:
                        inside += 1
                    if k % checkpoint == 0:
                        checkpoints.append(k)
                        await c.upload_blob(
                            blob_name,
                            json.dumps({
                                "worker": i,
                                "inside": inside,
                                "total":  k,
                                "checkpoints": checkpoints,
                                "done":   k == total,
                            }).encode(),
                            overwrite=True,
                        )
                print(f"DONE worker={i} inside={inside} total={total} ckpts={len(checkpoints)}")
            finally:
                await svc.close()
                await cred.close()

        asyncio.run(main())
    """).strip()


    async def run_worker(client: SandboxGroupClient, i: int) -> str:
        poller = await client.begin_create_sandbox(
            disk="python-3.14",
            labels={"swarm": "shared-blob-memory", "worker": str(i)},
        )
        sandbox = await poller.result()
        try:
            # Install azure-identity + azure-storage-blob inside the worker.
            inst = await sandbox.exec(
                "pip install --quiet --break-system-packages "
                "azure-identity azure-storage-blob aiohttp"
            )
            if inst.exit_code != 0:
                return f"FAIL worker={i} install_exit={inst.exit_code} stderr={inst.stderr[:400]}"

            await sandbox.write_file("/tmp/worker.py", WORKER_PY.encode())

            env_prefix = (
                f'STORAGE_ACCOUNT={STORAGE_ACCT} '
                f'CONTAINER_NAME={CONTAINER} '
                f'RUN_ID={RUN_ID}'
            )
            result = await sandbox.exec(
                f"{env_prefix} python3 /tmp/worker.py {i} {DARTS} {CHECKPOINT}"
            )
            if result.exit_code != 0:
                return f"FAIL worker={i} exit={result.exit_code} stderr={result.stderr[:400]}"
            return (result.stdout or "").strip().splitlines()[-1]
        finally:
            await sandbox.delete()


    async def main():
        cred = ManagedIdentityCredential()
        # 1. Spawn workers via MI in the worker group.
        sb_client = SandboxGroupClient(
            endpoint_for_region(REGION),
            cred,
            subscription_id=SUBSCRIPTION,
            resource_group=RG,
            sandbox_group=WORKER_GROUP,
        )
        try:
            lines = await asyncio.gather(*(run_worker(sb_client, i) for i in range(WORKERS)))
            for line in lines:
                print(line)
        finally:
            await sb_client.close()

        # 2. Aggregate by reading every result blob from the shared container.
        blob = BlobServiceClient(
            f"https://{STORAGE_ACCT}.blob.core.windows.net",
            credential=cred,
        )
        try:
            c = blob.get_container_client(CONTAINER)
            results = []
            async for b in c.list_blobs(name_starts_with=f"{RUN_ID}/"):
                stream = await c.download_blob(b.name)
                results.append(json.loads(await stream.readall()))
            results.sort(key=lambda r: r["worker"])
            print("RESULT=" + json.dumps(results))
        finally:
            await blob.close()
            await cred.close()


    if __name__ == "__main__":
        asyncio.run(main())
''')


def _load_env() -> None:
    for parent in Path(__file__).resolve().parents:
        env = parent / ".env"
        if env.is_file():
            for line in env.read_text().splitlines():
                if line and not line.startswith("#") and "=" in line:
                    k, v = line.split("=", 1)
                    os.environ.setdefault(k.strip(), v.strip())
            break
    if not os.environ.get("ACA_SANDBOXGROUP_REGION"):
        sys.exit(
            "error: samples/.env missing required keys. Run:\n"
            "       python samples/sandboxes/setup/python/setup.py"
        )


def _assign_role(
    auth: AuthorizationManagementClient,
    scope: str,
    principal_id: str,
    role_name: str,
    principal_type: str = "ServicePrincipal",
) -> None:
    role_def = next(
        auth.role_definitions.list(scope, filter=f"roleName eq '{role_name}'"),
        None,
    )
    if role_def is None:
        sys.exit(f"error: role '{role_name}' not found at scope {scope}")
    # AAD replication for a brand-new MI principal can take 10-30s; retry.
    last_exc: Exception | None = None
    for attempt in range(10):
        try:
            auth.role_assignments.create(
                scope,
                str(uuid.uuid4()),
                {
                    "role_definition_id": role_def.id,
                    "principal_id": principal_id,
                    "principal_type": principal_type,
                },
            )
            return
        except HttpResponseError as exc:
            msg = str(exc)
            if "RoleAssignmentExists" in msg or "Conflict" in msg:
                return
            if "PrincipalNotFound" in msg or "does not exist in the directory" in msg:
                last_exc = exc
                time.sleep(5)
                continue
            raise
    raise RuntimeError(f"role grant '{role_name}' never succeeded: {last_exc}")


def _wait_for_principal(mgmt: SandboxGroupManagementClient, group: str) -> str:
    """SystemAssigned principalId may not appear immediately after create."""
    for _ in range(10):
        identity = mgmt.get_group(group).identity or {}
        pid = identity.get("principalId")
        if pid:
            return pid
        time.sleep(2)
    sys.exit(f"error: sandbox group '{group}' has no principalId after create")


def main() -> None:
    _load_env()
    subscription   = os.environ["AZURE_SUBSCRIPTION_ID"]
    resource_group = os.environ["ACA_RESOURCE_GROUP"]
    region         = os.environ["ACA_SANDBOXGROUP_REGION"]

    suffix       = uuid.uuid4().hex[:8]
    run_id       = uuid.uuid4().hex[:12]
    orch_group   = f"swarmblob-orch-{suffix}"
    worker_group = f"swarmblob-workers-{suffix}"
    # Storage account names: 3-24 lowercase alphanumeric.
    storage_name = f"swarmblob{suffix}"[:24]

    cred = DefaultAzureCredential()
    sb_mgmt   = SandboxGroupManagementClient(
        cred, subscription_id=subscription, resource_group=resource_group,
    )
    st_mgmt   = StorageManagementClient(cred, subscription)
    auth      = AuthorizationManagementClient(cred, subscription)

    orch_client: SandboxGroupClient | None = None
    orchestrator = None
    storage_created = False
    try:
        # ---- 1. Sandbox groups (both with SystemAssigned MI) ---------------
        print(f"==> Provisioning orchestrator group {orch_group!r} (SystemAssigned MI)...")
        sb_mgmt.begin_create_group(
            orch_group, region, identity={"type": "SystemAssigned"},
        ).result()
        orch_pid = _wait_for_principal(sb_mgmt, orch_group)
        print(f"    orchestrator MI principalId: {orch_pid}")

        print(f"==> Provisioning worker group {worker_group!r} (SystemAssigned MI)...")
        sb_mgmt.begin_create_group(
            worker_group, region, identity={"type": "SystemAssigned"},
        ).result()
        worker_pid = _wait_for_principal(sb_mgmt, worker_group)
        print(f"    worker MI principalId:       {worker_pid}")

        # ---- 2. Storage account + container --------------------------------
        print(f"==> Provisioning storage account {storage_name!r}...")
        st_mgmt.storage_accounts.begin_create(
            resource_group,
            storage_name,
            {
                "sku": {"name": "Standard_LRS"},
                "kind": "StorageV2",
                "location": region,
                "properties": {
                    "allowBlobPublicAccess": False,
                    "publicNetworkAccess": "Enabled",
                    "minimumTlsVersion": "TLS1_2",
                    "allowSharedKeyAccess": False,
                    "defaultToOAuthAuthentication": True,
                },
            },
        ).result()
        storage_created = True

        print(f"==> Provisioning container {CONTAINER_NAME!r}...")
        st_mgmt.blob_containers.create(
            resource_group, storage_name, CONTAINER_NAME, {},
        )

        # ---- 3. Role grants ------------------------------------------------
        worker_group_scope = (
            f"/subscriptions/{subscription}/resourceGroups/{resource_group}"
            f"/providers/Microsoft.App/sandboxGroups/{worker_group}"
        )
        container_scope = (
            f"/subscriptions/{subscription}/resourceGroups/{resource_group}"
            f"/providers/Microsoft.Storage/storageAccounts/{storage_name}"
            f"/blobServices/default/containers/{CONTAINER_NAME}"
        )

        print(f"==> Granting {SANDBOX_DATA_OWNER!r} on worker group → orch MI...")
        _assign_role(auth, worker_group_scope, orch_pid, SANDBOX_DATA_OWNER)

        print(f"==> Granting {BLOB_DATA_CONTRIBUTOR!r} on container → orch MI + worker MI + host user...")
        _assign_role(auth, container_scope, orch_pid,   BLOB_DATA_CONTRIBUTOR)
        _assign_role(auth, container_scope, worker_pid, BLOB_DATA_CONTRIBUTOR)
        host_user_oid = os.environ.get("HOST_USER_OBJECT_ID")
        if not host_user_oid:
            try:
                import subprocess
                host_user_oid = subprocess.check_output(
                    ["az", "ad", "signed-in-user", "show", "--query", "id", "-o", "tsv"],
                    text=True, stderr=subprocess.DEVNULL,
                ).strip()
            except Exception:
                host_user_oid = None
        if host_user_oid:
            _assign_role(auth, container_scope, host_user_oid, BLOB_DATA_CONTRIBUTOR, principal_type="User")
        else:
            print("    (skipped host-user grant; set HOST_USER_OBJECT_ID or `az login` to enable cross-check)")

        print(f"==> Waiting {RBAC_PROPAGATION_SECONDS}s for RBAC propagation...")
        time.sleep(RBAC_PROPAGATION_SECONDS)

        # ---- 4. Orchestrator sandbox + bootstrap ---------------------------
        print(f"==> Creating orchestrator sandbox (disk={ORCH_DISK!r}) in {orch_group!r}...")
        orch_client = SandboxGroupClient(
            endpoint_for_region(region), cred,
            subscription_id=subscription,
            resource_group=resource_group,
            sandbox_group=orch_group,
        )
        orchestrator = orch_client.begin_create_sandbox(
            disk=ORCH_DISK,
            labels={"swarm": "shared-blob-memory", "role": "orchestrator"},
        ).result()
        print(f"    orchestrator: {orchestrator.sandbox_id}")

        print("==> Downloading SDK wheel + uploading into orchestrator...")
        wheel_name = SDK_WHEEL_URL.rsplit("/", 1)[-1]
        with urllib.request.urlopen(SDK_WHEEL_URL) as resp:
            wheel_bytes = resp.read()
        orchestrator.write_file(f"/tmp/{wheel_name}", wheel_bytes)
        orchestrator.write_file("/tmp/spawn_workers.py", SPAWN_WORKERS_SCRIPT.encode())

        print("==> Installing SDK + blob deps inside orchestrator...")
        install = orchestrator.exec(
            "pip install --quiet --break-system-packages "
            f"/tmp/{wheel_name} azure-identity azure-storage-blob aiohttp"
        )
        if install.exit_code != 0:
            sys.exit(f"orchestrator pip install failed:\n{install.stderr}")

        # ---- 5. Run the swarm ---------------------------------------------
        print(f"==> Orchestrator: spawning {WORKERS} workers in {worker_group!r} via MI...")
        env_prefix = (
            f"AZURE_SUBSCRIPTION_ID={subscription} "
            f"ACA_RESOURCE_GROUP={resource_group} "
            f"WORKER_SANDBOX_GROUP={worker_group} "
            f"ACA_SANDBOXGROUP_REGION={region} "
            f"STORAGE_ACCOUNT={storage_name} "
            f"CONTAINER_NAME={CONTAINER_NAME} "
            f"RUN_ID={run_id} "
            f"WORKERS={WORKERS} "
            f"DARTS_PER_WORKER={DARTS_PER_WORKER} "
            f"CHECKPOINT_EVERY={CHECKPOINT_EVERY}"
        )
        run = orchestrator.exec(f"{env_prefix} python3 /tmp/spawn_workers.py")
        if run.exit_code != 0:
            sys.exit(
                f"spawn_workers.py failed (exit={run.exit_code}):\n"
                f"stdout: {run.stdout}\nstderr: {run.stderr}"
            )

        # ---- 6. Aggregate (host reads worker DONE lines + the blob payload)
        payload = None
        for line in (run.stdout or "").splitlines():
            if line.startswith("DONE "):
                tokens = dict(t.split("=") for t in line.split()[1:] if "=" in t)
                print(
                    f"    worker {tokens.get('worker')}: "
                    f"{tokens.get('ckpts')} checkpoints, "
                    f"{int(tokens.get('inside', 0)):,} / "
                    f"{int(tokens.get('total', 0)):,} inside"
                )
            elif line.startswith("RESULT="):
                payload = json.loads(line[len("RESULT="):])
        if payload is None:
            sys.exit(f"no RESULT= line in orchestrator stdout:\n{run.stdout}")

        print(f"==> Reading {len(payload)} result blobs from shared container (host-side cross-check)...")
        host_blob = BlobServiceClient(
            f"https://{storage_name}.blob.core.windows.net", credential=cred,
        )
        host_results = []
        try:
            c = host_blob.get_container_client(CONTAINER_NAME)
            for b in c.list_blobs(name_starts_with=f"{run_id}/"):
                host_results.append(json.loads(c.download_blob(b.name).readall()))
        finally:
            host_blob.close()
        host_results.sort(key=lambda r: r["worker"])
        assert len(host_results) == WORKERS, (
            f"host-side blob count {len(host_results)} != WORKERS {WORKERS}"
        )

        total_inside = sum(r["inside"] for r in payload)
        total_darts  = sum(r["total"]  for r in payload)
        pi_est = 4.0 * total_inside / total_darts
        from math import pi
        err = abs(pi_est - pi)
        print(f"==> Aggregating across {total_darts:,} darts...")
        print(f"    π ≈ {pi_est:.6f}  (error {err:.2e})")
    finally:
        print("==> Cleaning up orchestrator + storage + both groups...")
        if orchestrator is not None:
            try:
                orchestrator.delete()
            except Exception as exc:
                print(f"    cleanup warning (orchestrator): {exc}")
        if orch_client is not None:
            orch_client.close()
        for grp in (orch_group, worker_group):
            try:
                sb_mgmt.delete_group(grp)
            except Exception as exc:
                print(f"    cleanup warning ({grp}): {exc}")
        if storage_created:
            try:
                st_mgmt.storage_accounts.delete(resource_group, storage_name)
            except Exception as exc:
                print(f"    cleanup warning (storage {storage_name}): {exc}")
        sb_mgmt.close()
        st_mgmt.close()
        auth.close()
        cred.close()
        print("==> Done.")


if __name__ == "__main__":
    main()
