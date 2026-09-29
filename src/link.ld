/* SPDX-License-Identifier: GPL-2.0-or-later */
/* 512 KB boot ROM mapped at 0x00000000 on the master SH-2 */
MEMORY { rom (rx) : ORIGIN = 0x00000000, LENGTH = 512K }
SECTIONS {
  .text : { *(.text) *(.rodata*) } > rom
  /* Fixed entry point some boot loaders call (see loadcd.s) */
  .fixed6480 0x6480 : { *(.fixed6480) } > rom
  ASSERT(ADDR(.text) + SIZEOF(.text) <= 0x6480, "code has grown into 0x6480")
}
