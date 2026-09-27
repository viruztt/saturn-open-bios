/* SPDX-License-Identifier: GPL-2.0-or-later */
/* 512 KB boot ROM mapped at 0x00000000 on the master SH-2 */
MEMORY { rom (rx) : ORIGIN = 0x00000000, LENGTH = 512K }
SECTIONS {
  .text : { *(.text) *(.rodata*) } > rom
}
