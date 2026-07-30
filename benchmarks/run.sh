#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
OUT="$ROOT/out"
mkdir -p "$OUT"
TS="$(date -u +%Y%m%dT%H%M%SZ)"
# Placeholder: wire real load once smoke images are available in CI.
cat > "$OUT/summary-$TS.json" <<JSON
{
  "generated_at": "$TS",
  "note": "stub — replace with measured values from CI harness",
  "agent": {
    "spans_per_sec": null,
    "bytes_per_span": null
  },
  "clickhouse": {
    "cpu_per_1k_spans_sec": null
  }
}
JSON
echo "Wrote $OUT/summary-$TS.json"
