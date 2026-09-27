# SaturnOpenBios

Free, clean-room replacement boot ROM for the Sega Saturn (emulators and MiSTer).

    sudo apt install binutils-sh-elf yabause xvfb x11-apps imagemagick
    make          # -> build/saturn-open-bios.bin (512 KB)
    make run      # boots it in Yabause headlessly, saves build/screen.png

Layout: `src/` SH-2 sources and linker script, `tools/` test scripts,
`test/` placeholder disc image, `docs/PLAN.md` roadmap and research notes.

## Licence

GPL-2.0-or-later (see `COPYING`). Clean-room: no code or data from Sega's BIOS.
