#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FG="$ROOT/tools/FlameGraph"
RES="$ROOT/results"
BENCH_ARGS="${BENCH_ARGS:-}"
GTIME="${GTIME:-/usr/bin/time}"

find_perf() {
    if [[ -n "${PERF:-}" ]]; then echo "$PERF"; return; fi
    if perf --version >/dev/null 2>&1; then echo perf; return; fi
    # Ubuntu's /usr/bin/perf is a wrapper that refuses to run when no linux-tools
    # package matches `uname -r` (WSL, custom kernels); any installed build works.
    local p
    for p in /usr/lib/linux-tools/*/perf /usr/lib/linux-tools-*/perf; do
        [[ -x "$p" ]] && { echo "$p"; return; }
    done
    echo "perf not found: run scripts/setup.sh" >&2
    exit 1
}
PERF="$(find_perf)"

bin_of() {
    local b="$ROOT/build/bench_$1"
    make -C "$ROOT" -s "build/bench_$1" >&2
    echo "$b"
}

outdir() {
    local d="$RES/$1"
    mkdir -p "$d"
    echo "$d"
}

say() { printf '\n\033[1m$ %s\033[0m\n' "$*" >&2; }

fix_owner() {
    if [[ -n "${SUDO_USER:-}" ]]; then
        chown -R "$SUDO_USER:$(id -gn "$SUDO_USER")" "$RES" 2>/dev/null || true
    fi
}

# Folded stacks -> share of samples where FUNC is the leaf frame (self time).
leaf_share() {
    awk '{ n = $NF; $NF = ""; k = split($0, f, ";"); leaf = f[k]; gsub(/ +$/, "", leaf);
           s[leaf] += n; t += n }
         END { for (x in s) printf "%7.2f%%  %s\n", 100 * s[x] / t, x }' "$1" |
        sort -rn | head -n "${2:-12}"
}
