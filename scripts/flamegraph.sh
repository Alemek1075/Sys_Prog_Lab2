#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

usage() {
    cat >&2 <<EOF
usage: $0 VARIANT [-a] [-F HZ]
  VARIANT  O0 | O2 | O3 | O3n | O3n512 | src
  -a       whole system while the program runs (needs perf_event_paranoid <= 0 or sudo)
  -F HZ    sampling frequency, default 999 (99 with -a)
result: results/VARIANT/flame_{prog,system}.svg
EOF
    exit 2
}

[[ $# -ge 1 ]] || usage
V=$1; shift
SYS=0; FREQ=""
while [[ $# -gt 0 ]]; do
    case $1 in
        -a) SYS=1 ;;
        -F) FREQ=$2; shift ;;
        *) usage ;;
    esac
    shift
done
[[ -d "$FG" ]] || { echo "tools/FlameGraph missing: run scripts/setup.sh" >&2; exit 1; }

BIN=$(bin_of "$V")
OUT=$(outdir "$V")
if ((SYS)); then
    TAG=system; FREQ=${FREQ:-99}; REC=(-a -g -F "$FREQ")
else
    TAG=prog; FREQ=${FREQ:-999}; REC=(-g -F "$FREQ")
fi
P="$OUT/flame_$TAG"

say "$PERF record ${REC[*]} -o $P.data -- $BIN -q $BENCH_ARGS"
$PERF record "${REC[@]}" -o "$P.data" -- "$BIN" -q $BENCH_ARGS

say "$PERF script -i $P.data > $P.perf"
$PERF script -i "$P.data" > "$P.perf" 2>/dev/null

say "stackcollapse-perf.pl $P.perf > $P.folded"
"$FG/stackcollapse-perf.pl" "$P.perf" > "$P.folded"

say "flamegraph.pl $P.folded > $P.svg"
"$FG/flamegraph.pl" --title "bench_$V, $TAG, ${FREQ} Hz" --countname samples \
    "$P.folded" > "$P.svg"

echo
echo "self time by function (leaf frames):"
leaf_share "$P.folded" | tee "$P.top.txt"
echo
echo "open: $P.svg"
fix_owner
