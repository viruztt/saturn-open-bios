# SPDX-License-Identifier: GPL-2.0-or-later
AS      = sh-elf-as
LD      = sh-elf-ld
OBJCOPY = sh-elf-objcopy
ASFLAGS = --isa=sh2 --big

all: build/saturn-open-bios.bin

build/%.o: src/%.s | build
	$(AS) $(ASFLAGS) -o $@ $<

OBJS = build/boot.o build/init.o build/sys.o build/bup.o build/cd.o build/disc.o build/console.o build/font.o

build/saturn-open-bios.elf: $(OBJS) src/link.ld
	$(LD) -EB -T src/link.ld -o $@ $(OBJS)

# The console expects exactly 512 KB; pad with 0xFF like an erased EPROM
build/saturn-open-bios.bin: build/saturn-open-bios.elf
	$(OBJCOPY) -O binary --pad-to 0x80000 --gap-fill 0xFF $< $@

build:
	mkdir -p build

# Test disc: our own IP.BIN (placeholder security area) + a first read file
build/testdisc/%.o: testdisc/%.s
	mkdir -p build/testdisc
	$(AS) $(ASFLAGS) -o $@ $<

build/testdisc/%.bin: build/testdisc/%.o
	$(LD) -EB -e 0 -Ttext $(if $(findstring ip,$*),0x06002000,0x06004000) -o $(@:.bin=.elf) $<
	$(OBJCOPY) -O binary -j .text $(@:.bin=.elf) $@

build/testdisc.iso: tools/mktestdisc.py build/testdisc/ip.bin build/testdisc/prog.bin
	python3 tools/mktestdisc.py build/testdisc/ip.bin build/testdisc/prog.bin $@

clean:
	rm -rf build

.PHONY: all clean
.PRECIOUS: build/testdisc/%.o

run: build/saturn-open-bios.bin build/testdisc.iso
	sh tools/run-yabause.sh
.PHONY: run
