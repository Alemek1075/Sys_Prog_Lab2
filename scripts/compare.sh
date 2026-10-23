#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
HERE="$(dirname "${BASH_SOURCE[0]}")"

if [[ $# -gt 2 ]]; then
    cat >&2 <<EOF
usage: $0 [BEFORE] [AFTER]          default: O0 O3n
  O0 -> O3n   effect of compiler flags
  O3n -> src  effect of the source change (matmul ijk -> ikj)
env SKIP_ENERGY=1 skips the RAPL part, SKIP_RUN=1 reuses existing results
writes results/compare_BEFORE_vs_AFTER/
EOF
    exit 2
fi
A=${1:-O0}
B=${2:-O3n}
D="$RES/compare_${A}_vs_${B}"
mkdir -p "$D"

if [[ -z "${SKIP_RUN:-}" ]]; then
    for V in "$A" "$B"; do
        "$HERE/stats.sh" "$V"
        "$HERE/flamegraph.sh" "$V"
        if [[ -z "${SKIP_ENERGY:-}" ]]; then
            "$HERE/energy.sh" "$V" || echo "energy.sh failed for $V, continuing without energy" >&2
        fi
    done
fi

FA="$RES/$A/flame_prog.folded"
FB="$RES/$B/flame_prog.folded"
if [[ -f "$FA" && -f "$FB" && -d "$FG" ]]; then
    "$FG/difffolded.pl" -n "$FA" "$FB" |
        "$FG/flamegraph.pl" --title "$A -> $B, shape of $B, red = more samples, blue = fewer (normalised)" \
        > "$D/flame_diff.svg"
    "$FG/difffolded.pl" -n "$FB" "$FA" |
        "$FG/flamegraph.pl" --negate --title "$A -> $B, shape of $A, blue = what disappeared (normalised)" \
        > "$D/flame_diff_negated.svg"
    paste <(echo "$A"; leaf_share "$FA" 8) <(echo "$B"; leaf_share "$FB" 8) |
        awk -F'\t' '{ printf "%-36s %s\n", $1, $2 }' > "$D/self_time.txt"
fi

for F in matmul blur saxpy; do
    "$HERE/asm_diff.sh" "$A" "$B" "$F" "$D/asm" >/dev/null
done

time_kv() {
    awk -F': ' '
    function secs(s,   p, k) { k = split(s, p, ":"); return k == 3 ? p[1] * 3600 + p[2] * 60 + p[3] : p[1] * 60 + p[2] }
    /Elapsed/                 { print "wall time, s",          secs($NF) }
    /User time/               { print "user time, s",          $NF }
    /System time/             { print "system time, s",        $NF }
    /Percent of CPU/          { sub(/%/, "", $NF); print "CPU, %", $NF }
    /Maximum resident/        { print "max RSS, KiB",          $NF }
    /Minor .*page faults/     { print "minor page faults",     $NF }
    /Voluntary context/       { print "voluntary ctx switches", $NF }
    /Involuntary context/     { print "involuntary ctx switches", $NF }' "$1"
}
stat_kv() {
    awk -F, '!/^#/ && NF > 3 && $1 !~ /^</ { print $3, $1 }' "$1"
}
energy_kv() {
    awk -F, 'NR > 1 && $2 ~ /^SYSTEM/ {
        print "energy: system P_run, W", $6
        print "energy: J/run above idle", $9
        print "energy: J/run CPU-share", $10 }' "$1"
}

collect() {
    local V=$1
    [[ -f "$RES/$V/time.txt" ]] && time_kv "$RES/$V/time.txt" | sed 's/ \([^ ]*\)$/\t\1/'
    [[ -f "$RES/$V/stat.csv" ]] && stat_kv "$RES/$V/stat.csv" | sed 's/ \([^ ]*\)$/\t\1/'
    [[ -f "$RES/$V/energy.csv" ]] && energy_kv "$RES/$V/energy.csv" | sed 's/ \([^ ]*\)$/\t\1/'
    true
}

{
    printf '%-34s %16s %16s %10s\n' metric "$A" "$B" "$B/$A"
    awk -F'\t' '
    NR == FNR { a[$1] = $2; if (!($1 in seen)) { seen[$1] = 1; ord[++n] = $1 }; next }
    { b[$1] = $2; if (!($1 in seen)) { seen[$1] = 1; ord[++n] = $1 } }
    END {
        for (i = 1; i <= n; i++) {
            k = ord[i]
            r = (a[k] + 0 != 0 && k in b) ? sprintf("%.3f", b[k] / a[k]) : "-"
            printf "%-34s %16s %16s %10s\n", k, (k in a ? a[k] : "-"), (k in b ? b[k] : "-"), r
        }
    }' <(collect "$A") <(collect "$B")
    echo
    [[ -f "$D/self_time.txt" ]] && { echo "self time by function:"; cat "$D/self_time.txt"; echo; }
    for F in matmul blur saxpy; do cat "$D/asm/$F.profile.txt"; echo; done
} | tee "$D/summary.txt"

echo "flame graphs: $RES/$A/flame_prog.svg  $RES/$B/flame_prog.svg  $D/flame_diff*.svg"
fix_owner
