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

G2 and G3 are built. [mac/](mac) builds Lemonade Remixed.app, which installs the original from your own `Setup.exe` into a private Wine setup, registers it, and plays it in a resizable native window with a sharp picture and mute, while Wine stays completely out of sight. The helper inside Wine lives in [runtime/helper](runtime/helper) and the in-game agent (audio volume and frame tap) in [runtime/agent](runtime/agent). Build with `mac/bundle.sh` (needs Wine Stable from Homebrew and LLVM).
