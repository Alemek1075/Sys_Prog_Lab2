#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

usage() {
    cat >&2 <<EOF
usage: $0 VARIANT
env:   IDLE_SEC=15   idle baseline length
       MIN_SEC=15    the program is rerun until at least this long has passed
       RAPL_DIR=/sys/class/powercap
writes results/VARIANT/energy.txt, energy.csv, energy_perf.txt
EOF
    exit 2
}
[[ $# -eq 1 ]] || usage
V=$1
IDLE_SEC=${IDLE_SEC:-15}
MIN_SEC=${MIN_SEC:-15}
RAPL=${RAPL_DIR:-/sys/class/powercap}

mapfile -t DOMS < <(ls -d "$RAPL"/intel-rapl:* 2>/dev/null | sort -V)
if [[ ${#DOMS[@]} -eq 0 ]]; then
    echo "no RAPL domains in $RAPL" >&2
    echo "VMs and WSL2 do not expose RAPL; boot Linux on the bare machine (a live USB is enough)" >&2
    exit 1
fi
# energy_uj is root-only since Linux 5.10 (PLATYPUS side channel).
if ! cat "${DOMS[0]}/energy_uj" >/dev/null 2>&1; then
    if [[ $EUID -ne 0 ]]; then
        exec sudo -E env "PATH=$PATH" bash "$0" "$@"
    fi
    echo "cannot read ${DOMS[0]}/energy_uj even as root" >&2
    exit 1
fi
[[ -x "$GTIME" ]] || { echo "GNU time not found at $GTIME" >&2; exit 1; }

BIN=$(bin_of "$V")
OUT=$(outdir "$V")
TMP="$OUT/.energy"
mkdir -p "$TMP"

snap() {
    local d
    for d in "${DOMS[@]}"; do
        printf '%s %s %s %s\n' "${d##*/}" "$(cat "$d/name")" \
            "$(cat "$d/energy_uj")" "$(cat "$d/max_energy_range_uj")"
    done
}
# user nice system irq softirq steal, in clock ticks; idle and iowait excluded
cpu_busy() { awk '/^cpu /{ print $2 + $3 + $4 + $7 + $8 + $9 }' /proc/stat; }
now() { date +%s.%N; }

echo "domains: $(for d in "${DOMS[@]}"; do printf '%s ' "$(cat "$d/name")"; done)"
echo "idle baseline ${IDLE_SEC}s, keep the machine alone"
sync
sleep 2
snap > "$TMP/idle0"; T0=$(now)
sleep "$IDLE_SEC"
snap > "$TMP/idle1"; T1=$(now)

echo "running bench_$V for >= ${MIN_SEC}s"
: > "$TMP/runs"
B0=$(cpu_busy)
snap > "$TMP/run0"; S0=$(now)
while :; do
    "$GTIME" -f "%e %U %S" -a -o "$TMP/runs" "$BIN" -q $BENCH_ARGS >/dev/null
    awk -v a="$S0" -v b="$(now)" -v m="$MIN_SEC" 'BEGIN { exit !(b - a >= m) }' && break
done
snap > "$TMP/run1"; S1=$(now)
B1=$(cpu_busy)

HZ=$(getconf CLK_TCK)
read -r RUNS CPU_PROG WALL_PROG < <(awk '{ n++; c += $2 + $3; w += $1 } END { print n, c, w }' "$TMP/runs")

awk -v Ti="$(awk -v a="$T0" -v b="$T1" 'BEGIN{print b-a}')" \
    -v Tr="$(awk -v a="$S0" -v b="$S1" 'BEGIN{print b-a}')" \
    -v busy="$(awk -v a="$B0" -v b="$B1" -v hz="$HZ" 'BEGIN{print (b-a)/hz}')" \
    -v runs="$RUNS" -v cpu="$CPU_PROG" -v wall="$WALL_PROG" -v csv="$OUT/energy.csv" -v var="$V" '
function wrap(x, m) { return x < 0 ? x + m : x }
FNR == 1 { f++ }
{ id = $1; nm[id] = $2; mx[id] = $4; e[f, id] = $3; if (f == 1) ord[++n] = id }
END {
    share = busy > 0 ? cpu / busy : 0; if (share > 1) share = 1
    printf "variant %s: %d runs, %.2f s wall, program CPU time %.2f s, all busy CPU time %.2f s, share %.3f\n\n",
        var, runs, Tr, cpu, busy, share
    printf "%-18s %9s %9s %9s %10s %12s %12s\n", "domain", "P_idle,W", "P_run,W", "E_run,J",
        "E_dyn,J", "prog J/run", "prog J/run"
    printf "%-18s %9s %9s %9s %10s %12s %12s\n", "", "", "", "", "", "(marginal)", "(CPU share)"
    print "variant,domain,runs,T_run_s,P_idle_W,P_run_W,E_run_J,E_dyn_J,J_per_run_marginal,J_per_run_share,cpu_share" > csv
    for (i = 1; i <= n; i++) {
        id = ord[i]; label = nm[id]
        if (split(id, p, ":") == 3) label = nm[p[1] ":" p[2]] "/" nm[id]
        Pi = wrap(e[2, id] - e[1, id], mx[id]) / 1e6 / Ti
        Er = wrap(e[4, id] - e[3, id], mx[id]) / 1e6
        Ed = Er - Pi * Tr
        row(label, Pi, Er / Tr, Er, Ed)
        if (nm[id] ~ /^package/) { sPi += Pi; sEr += Er; npk++ }
        if (nm[id] == "dram" || nm[id] == "psys") { xPi[nm[id]] += Pi; xEr[nm[id]] += Er }
    }
    if ("psys" in xEr) row("SYSTEM=psys", xPi["psys"], xEr["psys"] / Tr, xEr["psys"], xEr["psys"] - xPi["psys"] * Tr)
    else if (npk) {
        sPi += xPi["dram"]; sEr += xEr["dram"]
        row("SYSTEM=pkg+dram", sPi, sEr / Tr, sEr, sEr - sPi * Tr)
    }
}
function row(l, Pi, Pr, Er, Ed) {
    printf "%-18s %9.2f %9.2f %9.1f %10.1f %12.2f %12.2f\n", l, Pi, Pr, Er, Ed, Ed / runs, Ed * share / runs
    printf "%s,%s,%d,%.3f,%.3f,%.3f,%.3f,%.3f,%.4f,%.4f,%.4f\n", var, l, runs, Tr, Pi, Pr, Er, Ed,
        Ed / runs, Ed * share / runs, share >> csv
}' "$TMP/idle0" "$TMP/idle1" "$TMP/run0" "$TMP/run1" | tee "$OUT/energy.txt"

EV=$($PERF list 2>/dev/null | awk '/power\/energy-(pkg|cores|ram|psys)\//{ print $1 }' | sort -u | paste -sd, -)
if [[ -n "$EV" ]]; then
    say "$PERF stat -a -e $EV -- $BIN -q $BENCH_ARGS"
    $PERF stat -a -e "$EV" -o "$OUT/energy_perf.txt" -- "$BIN" -q $BENCH_ARGS >/dev/null
    cat "$OUT/energy_perf.txt"
fi
fix_owner
