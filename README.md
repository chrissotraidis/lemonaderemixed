# Lemonade Remixed

The original 2002 lemonade stand game *Lemonade Tycoon Deluxe* (Hexacto), running unchanged under Wine inside a native Mac app that makes it better: sharp and fullscreen at any size, upscaled art, sound controls and tips, playable from the MacBook notch, and a desktop widget for managing the stand.

## How the original content is handled

This repository holds only our own code and documentation. Players bring their own copy of the original installer; Lemonade Remixed unpacks it on their machine and uses its art and sound from there. Nothing from the original game is committed or distributed here.

- [tools/unpack_installer.py](tools/unpack_installer.py) unpacks the original Windows installer (`Setup.exe`) and checks every file against the CRC-32 the installer records.
- [docs/ORIGINAL.md](docs/ORIGINAL.md) explains how to run the original under Wine for reference.

## Documents

- [docs/MECHANICS.md](docs/MECHANICS.md): how the original game works, with the numbers measured so far.
- [docs/PLAN.md](docs/PLAN.md): what the remix adds and how it works.
- [docs/GOALS.md](docs/GOALS.md): the build plan as goals, each with its test.

## Status

Early prototype. The original runs under Wine and its economy is documented. [mac/](mac) holds a first shell that mirrors the live game into a resizable window and beside the notch and sends input back through the helper in [runtime/helper](runtime/helper); it proves the plumbing, not the design. Next is G2: one app that installs and runs everything with no Wine visible.
