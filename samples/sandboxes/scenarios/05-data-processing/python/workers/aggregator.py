"""Aggregator — single-shot summary over all processed batches.

Reads every ``/mnt/shared/processed/batch-*.jsonl`` written by the
transformer, computes top-N summaries, and emits a single
``RESULT=<json>`` line so the host script can parse it. Also persists
the same payload to ``/mnt/shared/summary/report.json`` for any later
consumer that wants to read it from the shared volume.
"""

from __future__ import annotations

import glob
import json
import os
import sys
import time
from collections import Counter

MOUNT = os.environ.get("MOUNTPOINT", "/mnt/shared")
PROCESSED_DIR = f"{MOUNT}/processed"
SUMMARY_DIR = f"{MOUNT}/summary"
TOP_USERS = int(os.environ.get("TOP_USERS", "10"))
TOP_HOURS = int(os.environ.get("TOP_HOURS", "5"))


def main() -> int:
    os.makedirs(SUMMARY_DIR, exist_ok=True)
    t0 = time.perf_counter()

    files = sorted(glob.glob(f"{PROCESSED_DIR}/batch-*.jsonl"))
    if not files:
        print("ERROR no processed batches found at " + PROCESSED_DIR, file=sys.stderr)
        return 1

    total = 0
    by_type: Counter[str] = Counter()
    by_user: Counter[str] = Counter()
    by_hour: Counter[int] = Counter()
    revenue_count = 0
    total_value = 0.0

    for path in files:
        with open(path, encoding="utf-8") as f:
            for raw in f:
                raw = raw.strip()
                if not raw:
                    continue
                evt = json.loads(raw)
                total += 1
                by_type[evt.get("event_type", "unknown")] += 1
                by_user[evt.get("user_id", "unknown")] += 1
                by_hour[int(evt.get("hour", -1))] += 1
                if evt.get("is_revenue_event"):
                    revenue_count += 1
                v = evt.get("value")
                if isinstance(v, (int, float)):
                    total_value += float(v)

    report = {
        "files_read": len(files),
        "events_total": total,
        "revenue_events": revenue_count,
        "total_value": round(total_value, 2),
        "avg_value": round(total_value / total, 4) if total else 0.0,
        "events_by_type": dict(by_type.most_common()),
        "top_users": by_user.most_common(TOP_USERS),
        "top_hours": by_hour.most_common(TOP_HOURS),
    }

    out_path = f"{SUMMARY_DIR}/report.json"
    tmp = f"{out_path}.tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(report, f, indent=2)
        f.flush()
        os.fsync(f.fileno())
    os.replace(tmp, out_path)

    elapsed = time.perf_counter() - t0
    print(f"AGGREGATED files={len(files)} events={total} elapsed_s={elapsed:.2f}")
    # Emit a single machine-readable line the host can pluck out.
    print("RESULT=" + json.dumps(report))
    return 0


if __name__ == "__main__":
    sys.exit(main())
