CC      ?= gcc
SRC     := src/bench.c
BUILD   := build
ASMDIR  := $(BUILD)/asm

PROF    := -g -fno-omit-frame-pointer
ASMFLG  := -S -masm=intel -fno-asynchronous-unwind-tables -fno-dwarf2-cfi-asm

CFLAGS_O0     := -O0
CFLAGS_O2     := -O2
CFLAGS_O3     := -O3
CFLAGS_O3n    := -O3 -march=native
CFLAGS_O3n512 := -O3 -march=native -mprefer-vector-width=512
CFLAGS_src    := -O3 -march=native -DOPT_SRC

VARIANTS := O0 O2 O3 O3n O3n512 src
BINS     := $(VARIANTS:%=$(BUILD)/bench_%)
ASMS     := $(VARIANTS:%=$(ASMDIR)/bench_%.s)

.PHONY: all asm clean help

all: $(BINS)

asm: $(ASMS)

$(BUILD)/bench_%: $(SRC) Makefile | $(BUILD)
	$(CC) -std=gnu11 -Wall -Wextra $(CFLAGS_$*) $(PROF) $< -o $@

$(ASMDIR)/bench_%.s: $(SRC) Makefile | $(ASMDIR)
	$(CC) -std=gnu11 $(CFLAGS_$*) $(ASMFLG) $< -o $@

$(BUILD) $(ASMDIR):
	mkdir -p $@

clean:
	rm -rf $(BUILD) results

help:
	@echo "make            build/bench_{O0,O2,O3,O3n,O3n512,src}"
	@echo "make asm        build/asm/bench_*.s (Intel syntax)"
	@echo ""
	@echo "  O0      -O0, baseline"
	@echo "  O2      -O2"
	@echo "  O3      -O3, SSE2 only (x86-64 baseline ISA)"
	@echo "  O3n     -O3 -march=native (AVX2/AVX-512, 256-bit vectors by default)"
	@echo "  O3n512  same, forced 512-bit vectors"
	@echo "  src     -O3 -march=native + source change: matmul loop order ijk -> ikj"
	@echo ""
	@echo "scripts/setup.sh                 perf, GNU time, FlameGraph"
	@echo "scripts/flamegraph.sh VARIANT    flame graph of one run (-a for whole system)"
	@echo "scripts/stats.sh VARIANT         time -v, perf stat -d, perf record/report"
	@echo "scripts/energy.sh VARIANT        RAPL energy: system and program-only"
	@echo "scripts/asm_diff.sh A B FUNC     disassembly of one function, side by side"
	@echo "scripts/compare.sh BEFORE AFTER  all of the above + summary table + diff flame graph"
