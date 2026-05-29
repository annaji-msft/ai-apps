"""Producer — generates synthetic event batches into /mnt/shared/raw/.

Runs inside the producer sandbox. Writes BATCHES of EVENTS_PER_BATCH
JSON-lines events to ``/mnt/shared/raw/batch-NNN.jsonl`` with atomic
rename, then drops a sentinel ``.producer-done`` so the transformer
knows when to stop polling.

No Azure SDK is used — every write is a plain ``open()`` against the
mounted AzureBlob volume.
"""

from __future__ import annotations

import json
import os
import random
import sys
import time
import uuid

MOUNT = os.environ.get("MOUNTPOINT", "/mnt/shared")
RAW_DIR = f"{MOUNT}/raw"
BATCHES = int(os.environ.get("BATCHES", "20"))
EVENTS_PER_BATCH = int(os.environ.get("EVENTS_PER_BATCH", "100"))
BATCH_DELAY_S = float(os.environ.get("BATCH_DELAY_S", "0.5"))

EVENT_TYPES = ["page_view", "click", "purchase", "signup", "logout"]
USER_POOL = [f"u{n:04d}" for n in range(100)]


def write_atomic(path: str, payload: str) -> None:
    """Write `payload` to `path` atomically (write tmp, fsync, rename)."""
    tmp = f"{path}.tmp.{uuid.uuid4().hex[:6]}"
    with open(tmp, "w", encoding="utf-8") as f:
        f.write(payload)
        f.flush()
        os.fsync(f.fileno())
    os.replace(tmp, path)


def main() -> int:
    os.makedirs(RAW_DIR, exist_ok=True)
    rng = random.Random(int(os.environ.get("SEED", "42")))
    total = 0
    t0 = time.perf_counter()
    for batch_i in range(BATCHES):
        ts_base = int(time.time() * 1000)
        lines = []
        for j in range(EVENTS_PER_BATCH):
            evt = {
                "ts": ts_base + j,
                "user_id": rng.choice(USER_POOL),
                "event_type": rng.choices(
                    EVENT_TYPES,
                    weights=[60, 25, 4, 1, 10],  # page_view dominates
                    k=1,
                )[0],
                "value": round(rng.random() * 100, 2),
                "session_id": uuid.uuid4().hex[:12],
            }
            lines.append(json.dumps(evt))
        payload = "\n".join(lines) + "\n"
        path = f"{RAW_DIR}/batch-{batch_i:03d}.jsonl"
        write_atomic(path, payload)
        total += EVENTS_PER_BATCH
        print(f"PRODUCED batch={batch_i:03d} events={EVENTS_PER_BATCH} cumulative={total}", flush=True)
        if batch_i < BATCHES - 1:
            time.sleep(BATCH_DELAY_S)

    # Sentinel marking the producer is done — the transformer waits for this
    # before exiting its watch loop.
    write_atomic(f"{RAW_DIR}/.producer-done", str(int(time.time())))
    elapsed = time.perf_counter() - t0
    print(f"DONE producer batches={BATCHES} events={total} elapsed_s={elapsed:.2f}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
