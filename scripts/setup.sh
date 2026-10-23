#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if command -v apt-get >/dev/null; then
    sudo apt-get update
    sudo apt-get install -y build-essential time git linux-tools-common linux-tools-generic
    sudo apt-get install -y "linux-tools-$(uname -r)" ||
        echo "no linux-tools package for $(uname -r); scripts will use /usr/lib/linux-tools/*/perf"
elif command -v dnf >/dev/null; then
    sudo dnf install -y gcc make time git perf
elif command -v pacman >/dev/null; then
    sudo pacman -S --needed --noconfirm base-devel time git perf
else
    echo "unknown package manager: install gcc, make, GNU time, git, perf by hand" >&2
fi

if [[ ! -d "$ROOT/tools/FlameGraph" ]]; then
    git clone --depth 1 https://github.com/brendangregg/FlameGraph "$ROOT/tools/FlameGraph"
fi

make -C "$ROOT" all asm

echo
echo "kernel.perf_event_paranoid = $(cat /proc/sys/kernel/perf_event_paranoid)"
echo "kernel.kptr_restrict       = $(cat /proc/sys/kernel/kptr_restrict)"
echo "system-wide profiling (-a) and kernel symbols need:"
echo "  sudo sysctl -w kernel.perf_event_paranoid=-1 kernel.kptr_restrict=0"
if ls /sys/class/powercap/intel-rapl:* >/dev/null 2>&1; then
    echo "RAPL: $(cat /sys/class/powercap/intel-rapl:*/name 2>/dev/null | tr '\n' ' ')"
else
    echo "RAPL: not available here (VM or WSL?), energy.sh needs bare-metal Linux"
fi
