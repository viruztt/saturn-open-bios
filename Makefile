# SPDX-License-Identifier: GPL-2.0-or-later
AS      = sh-elf-as
LD      = sh-elf-ld
OBJCOPY = sh-elf-objcopy
ASFLAGS = --isa=sh2 --big

all: build/saturn-open-bios.bin

build/%.o: src/%.s | build
	$(AS) $(ASFLAGS) -o $@ $<

OBJS = build/boot.o build/init.o build/console.o build/font.o

build/saturn-open-bios.elf: $(OBJS) src/link.ld
	$(LD) -EB -T src/link.ld -o $@ $(OBJS)

# The console expects exactly 512 KB; pad with 0xFF like an erased EPROM
build/saturn-open-bios.bin: build/saturn-open-bios.elf
	$(OBJCOPY) -O binary --pad-to 0x80000 --gap-fill 0xFF $< $@

build:
	mkdir -p build

clean:
	rm -rf build test/dummy.iso

.PHONY: all clean

run: build/saturn-open-bios.bin test/dummy.iso
	sh tools/run-yabause.sh
.PHONY: run

test/dummy.iso: tools/mkdummydisc.py
	python3 tools/mkdummydisc.py
