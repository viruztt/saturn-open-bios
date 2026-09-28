# SPDX-License-Identifier: GPL-2.0-or-later
AS      = sh-elf-as
LD      = sh-elf-ld
OBJCOPY = sh-elf-objcopy
ASFLAGS = --isa=sh2 --big
# B: output directory for the BIOS (build/diag for make diag)
# DEFS: extra assembler symbols, e.g. --defsym DIAG=1
B       = build
DEFS    =

all: $(B)/saturn-open-bios.bin

$(B)/%.o: src/%.s | $(B)
	$(AS) $(ASFLAGS) $(DEFS) -o $@ $<

OBJS = $(addprefix $(B)/,boot.o init.o sys.o bup.o menu.o crash.o diag.o cd.o disc.o console.o font.o)

$(B)/saturn-open-bios.elf: $(OBJS) src/link.ld
	$(LD) -EB -T src/link.ld -o $@ $(OBJS)

# The console expects exactly 512 KB; pad with 0xFF like an erased EPROM
$(B)/saturn-open-bios.bin: $(B)/saturn-open-bios.elf
	$(OBJCOPY) -O binary --pad-to 0x80000 --gap-fill 0xFF $< $@

$(B):
	mkdir -p $(B)

# Debug build with compatibility diagnostics (src/diag.s) in build/diag/
diag:
	$(MAKE) B=build/diag DEFS="--defsym DIAG=1" build/diag/saturn-open-bios.bin
.PHONY: diag

# Test disc: our own IP.BIN (placeholder security area) + a first read file
build/testdisc/%.o: testdisc/%.s
	mkdir -p build/testdisc
	$(AS) $(ASFLAGS) -o $@ $<

build/testdisc/%.bin: build/testdisc/%.o
	$(LD) -EB -e 0 -Ttext $(if $(findstring ip,$*),0x06002000,0x06004000) -o $(@:.bin=.elf) $<
	$(OBJCOPY) -O binary -j .text $(@:.bin=.elf) $@

build/testdisc.iso: tools/mktestdisc.py build/testdisc/ip.bin build/testdisc/prog.bin
	python3 tools/mktestdisc.py build/testdisc/ip.bin build/testdisc/prog.bin $@

# The same disc as BIN/CUE with a CD-DA test tone as track 2 (for MiSTer)
build/testdisc-audio.bin: tools/mkaudiodisc.py build/testdisc.iso
	python3 tools/mkaudiodisc.py build/testdisc.iso $@ build/testdisc-audio.cue

clean:
	rm -rf build

.PHONY: all clean
.PRECIOUS: build/testdisc/%.o

run: build/saturn-open-bios.bin build/testdisc.iso
	sh tools/run-yabause.sh
.PHONY: run

# Boot any disc image in place (never copied): make run-image IMAGE=/path/game.cue
# The screenshot goes to build/image.png, which is not tracked.
# make run-image-diag does the same with the diagnostics build.
run-image: build/saturn-open-bios.bin
	test -n "$(IMAGE)"
	sh tools/run-yabause.sh "$(IMAGE)" build/image.png
run-image-diag: diag
	test -n "$(IMAGE)"
	BIOS=build/diag/saturn-open-bios.bin sh tools/run-yabause.sh "$(IMAGE)" build/image.png
.PHONY: run-image run-image-diag

# Play a disc image in a normal Yabause window (WSLg on Windows):
# make play IMAGE=/path/game.cue
play: build/saturn-open-bios.bin
	test -n "$(IMAGE)"
	yabause -a -b build/saturn-open-bios.bin -i "$(IMAGE)"
.PHONY: play
