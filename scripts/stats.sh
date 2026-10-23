#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

if [[ $# -ne 1 ]]; then
    cat >&2 <<EOF
usage: $0 VARIANT
writes results/VARIANT/: time.txt, stat.txt, stat.csv (3 runs), report*.txt, annotate.txt
EOF
    exit 2
fi
V=$1
BIN=$(bin_of "$V")
OUT=$(outdir "$V")
[[ -x "$GTIME" ]] || { echo "GNU time not found at $GTIME (apt install time)" >&2; exit 1; }

say "$GTIME --verbose $BIN $BENCH_ARGS"
"$GTIME" --verbose -o "$OUT/time.txt" "$BIN" $BENCH_ARGS | tee "$OUT/program.txt"
cat "$OUT/time.txt"

say "$PERF stat -d $BIN -q $BENCH_ARGS"
$PERF stat -d -o "$OUT/stat.txt" -- "$BIN" -q $BENCH_ARGS >/dev/null
cat "$OUT/stat.txt"

# Same counters, 3 runs, machine-readable: compare.sh builds its table from this.
$PERF stat -d -r 3 -x, -o "$OUT/stat.csv" -- "$BIN" -q $BENCH_ARGS >/dev/null

say "$PERF record -g -F 999 -o $OUT/record.data -- $BIN -q $BENCH_ARGS"
$PERF record -g -F 999 -o "$OUT/record.data" -- "$BIN" -q $BENCH_ARGS >/dev/null

say "$PERF report -i $OUT/record.data --stdio --no-children --sort dso,sym"
$PERF report -i "$OUT/record.data" --stdio --no-children --sort dso,sym \
    -g none --percent-limit 0.5 2>/dev/null | tee "$OUT/report.txt" | grep -v '^$'

$PERF report -i "$OUT/record.data" --stdio --children --sort sym \
    -g caller --percent-limit 2 > "$OUT/report_callgraph.txt" 2>/dev/null

HOT=$(awk '/^ +[0-9.]+%/ && $NF != "" { print $NF; exit }' "$OUT/report.txt")
if [[ -n "$HOT" ]]; then
    say "$PERF annotate -i $OUT/record.data --stdio -s $HOT"
    $PERF annotate -i "$OUT/record.data" --stdio -M intel -s "$HOT" \
        > "$OUT/annotate.txt" 2>/dev/null || true
    grep -E '^ +[0-9]+\.[0-9]+ +:' "$OUT/annotate.txt" | sort -rn | head -12 || true
fi
echo
echo "files: $OUT/{time.txt,stat.txt,stat.csv,report.txt,report_callgraph.txt,annotate.txt}"
fix_owner
