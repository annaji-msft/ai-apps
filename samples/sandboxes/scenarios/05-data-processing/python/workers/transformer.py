"""Transformer — enriches raw batches and writes processed records.

Runs inside the transformer sandbox concurrently with the producer.
Polls ``/mnt/shared/raw/`` for new ``batch-NNN.jsonl`` files, parses
each JSON line, enriches with derived fields, and writes
``/mnt/shared/processed/batch-NNN.jsonl``. Source files are moved to
``/mnt/shared/raw/.done/`` to mark them consumed so the polling loop
doesn't re-process them.

Stops when the producer has dropped ``raw/.producer-done`` and no new
files appear for ``QUIET_PERIOD_S`` seconds.
"""

from __future__ import annotations

import glob
import hashlib
import json
import os
import sys
import time
from datetime import datetime, timezone

MOUNT = os.environ.get("MOUNTPOINT", "/mnt/shared")
RAW_DIR = f"{MOUNT}/raw"
DONE_DIR = f"{RAW_DIR}/.done"
PROCESSED_DIR = f"{MOUNT}/processed"
PRODUCER_DONE_PATH = f"{RAW_DIR}/.producer-done"

POLL_S = float(os.environ.get("POLL_S", "0.5"))
QUIET_PERIOD_S = float(os.environ.get("QUIET_PERIOD_S", "5"))
MAX_LIFETIME_S = float(os.environ.get("MAX_LIFETIME_S", "120"))


def user_bucket(user_id: str, buckets: int = 10) -> int:
    h = hashlib.md5(user_id.encode("utf-8")).digest()
    return int.from_bytes(h[:4], "big") % buckets


def hour_of_day(ts_ms: int) -> int:
    return datetime.fromtimestamp(ts_ms / 1000, tz=timezone.utc).hour


def enrich(line: str) -> dict | None:
    line = line.strip()
    if not line:
        return None
    try:
        evt = json.loads(line)
    except json.JSONDecodeError:
        return None
    ts_ms = int(evt.get("ts", 0))
    return {
        **evt,
        "user_bucket": user_bucket(str(evt.get("user_id", ""))),
        "hour": hour_of_day(ts_ms),
        "is_revenue_event": evt.get("event_type") == "purchase",
    }


def process_batch(src_path: str) -> int:
    name = os.path.basename(src_path)
    out_path = f"{PROCESSED_DIR}/{name}"
    count = 0
    tmp = f"{out_path}.tmp"
    with open(src_path, encoding="utf-8") as fin, open(tmp, "w", encoding="utf-8") as fout:
        for raw_line in fin:
            enriched = enrich(raw_line)
            if enriched is None:
                continue
            fout.write(json.dumps(enriched) + "\n")
            count += 1
        fout.flush()
        os.fsync(fout.fileno())
    os.replace(tmp, out_path)
    # Move source out of the way so we don't pick it up again next poll.
    os.replace(src_path, f"{DONE_DIR}/{name}")
    return count


def main() -> int:
    os.makedirs(RAW_DIR, exist_ok=True)
    os.makedirs(DONE_DIR, exist_ok=True)
    os.makedirs(PROCESSED_DIR, exist_ok=True)

    t_start = time.perf_counter()
    last_progress = time.perf_counter()
    total_batches = 0
    total_events = 0

    while True:
        # Stop conditions
        if (time.perf_counter() - t_start) > MAX_LIFETIME_S:
            print(f"WARN transformer hit MAX_LIFETIME_S={MAX_LIFETIME_S}; bailing", flush=True)
            break

        candidates = sorted(glob.glob(f"{RAW_DIR}/batch-*.jsonl"))
        # Filter out partial writes (producer writes .tmp.* then renames)
        candidates = [c for c in candidates if not c.endswith(".tmp")]

        if candidates:
            for src in candidates:
                try:
                    events_in_batch = process_batch(src)
                except FileNotFoundError:
                    # Another rename race (shouldn't happen — single transformer) — skip.
                    continue
                total_batches += 1
                total_events += events_in_batch
                last_progress = time.perf_counter()
                print(
                    f"TRANSFORMED batch={os.path.basename(src)} events={events_in_batch} "
                    f"cumulative_batches={total_batches} cumulative_events={total_events}",
                    flush=True,
                )
            continue  # poll again immediately when we've drained the queue

        # No new files this poll. Exit if producer is done and quiet period elapsed.
        producer_done = os.path.exists(PRODUCER_DONE_PATH)
        if producer_done and (time.perf_counter() - last_progress) > QUIET_PERIOD_S:
            print(
                f"DRAIN producer-done and {QUIET_PERIOD_S}s quiet — exiting",
                flush=True,
            )
            break
        time.sleep(POLL_S)

    elapsed = time.perf_counter() - t_start
    print(
        f"DONE transformer batches={total_batches} events={total_events} elapsed_s={elapsed:.2f}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
