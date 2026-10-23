#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

if [[ $# -lt 3 ]]; then
    cat >&2 <<EOF
usage: $0 VARIANT_A VARIANT_B FUNCTION [OUTDIR]
  FUNCTION  matmul | blur | saxpy | fill | checksum
prints an instruction profile of FUNCTION in both binaries and writes
OUTDIR/FUNCTION.{A,B}.s (plain), .src.txt (interleaved with C source), .diff
EOF
    exit 2
fi
A=$1; B=$2; FN=$3
D=${4:-$RES/asm_${A}_vs_${B}}
mkdir -p "$D"

# GCC may clone a function and rename it (saxpy -> saxpy.constprop.0).
sym_of() {
    nm --defined-only "$1" | awk -v f="$2" '$3 == f || index($3, f ".") == 1 { print $3; exit }'
}

dis() {
    objdump -d --no-show-raw-insn -M intel --disassemble="$2" "$1" |
        awk '/^ +[0-9a-f]+:\t/ { sub(/^ +[0-9a-f]+:\t/, ""); print }'
}

profile() {
    awk '
    { n++; op = $1
      if (op ~ /^v?(add|sub|mul|div|max|min|sqrt)p[sd]$/ || op ~ /^vf(n)?m(add|sub)[0-9]+p[sd]$/) pk++
      if (op ~ /^v?(add|sub|mul|div|max|min|sqrt)s[sd]$/ || op ~ /^vf(n)?m(add|sub)[0-9]+s[sd]$/) sc++
      if (op ~ /^vf(n)?m(add|sub)/) fma++
      if (op ~ /^j/) jmp++
      if ($0 ~ /zmm/) z++; else if ($0 ~ /ymm/) y++; else if ($0 ~ /xmm/) x++
      if ($0 ~ /\[(rbp|rsp)/) stk++ }
    END { printf "%d %d %d %d %d %d %d %d %d\n", n, sc, pk, fma, x, y, z, stk, jmp }'
}

for V in "$A" "$B"; do
    BIN=$(bin_of "$V")
    S=$(sym_of "$BIN" "$FN")
    [[ -n "$S" ]] || { echo "no symbol $FN in $BIN (inlined?)" >&2; exit 1; }
    dis "$BIN" "$S" > "$D/$FN.$V.s"
    objdump -d -S --no-show-raw-insn -M intel --disassemble="$S" "$BIN" > "$D/$FN.$V.src.txt"
    printf '%s %s ' "$V" "$S"
    profile < "$D/$FN.$V.s"
done | awk -v fn="$FN" '
BEGIN { split("instructions,scalar FP (ss/sd),packed FP (ps/pd),FMA,uses xmm,uses ymm,uses zmm,stack [rbp/rsp] refs,jumps", L, ",") }
{ v[NR] = $1; s[NR] = $2; for (i = 3; i <= NF; i++) c[NR, i - 2] = $i }
END {
    printf "%-24s %16s %16s\n", fn, v[1] " (" s[1] ")", v[2] " (" s[2] ")"
    for (i = 1; i <= 9; i++) printf "%-24s %16d %16d\n", L[i], c[1, i], c[2, i]
}' | tee "$D/$FN.profile.txt"

diff -y -W 140 "$D/$FN.$A.s" "$D/$FN.$B.s" > "$D/$FN.diff" || true
echo "listings: $D/$FN.{$A,$B}.s  $D/$FN.{$A,$B}.src.txt  $D/$FN.diff"
