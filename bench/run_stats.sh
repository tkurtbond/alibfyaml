#!/usr/bin/env bash
# Runs a bench binary N times, extracts elapsed_seconds, prints mean/min/max/stddev.
# Usage: run_stats.sh <bench-binary> <fixture-path> [N (default 10)]
set -euo pipefail
BIN="$1"
ARG="$2"
N="${3:-10}"

times=()
for ((i=0; i<N; i++)); do
  line=$("$BIN" "$ARG" | grep elapsed_seconds)
  val=$(echo "$line" | sed -E 's/.*elapsed_seconds= *([0-9.]+).*/\1/')
  times+=("$val")
done

printf '%s\n' "${times[@]}" | awk '
{
  sum += $1; sumsq += $1*$1; n++;
  if (NR==1 || $1<min) min=$1;
  if (NR==1 || $1>max) max=$1;
}
END {
  mean = sum/n;
  var = sumsq/n - mean*mean;
  if (var < 0) var = 0;
  sd = sqrt(var);
  printf "n=%d mean=%.6f min=%.6f max=%.6f stddev=%.6f\n", n, mean, min, max, sd;
}'
