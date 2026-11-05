# Lemonade Remixed

A modern, full-resolution remake of the 2002 lemonade stand game *Lemonade Tycoon Deluxe* (Hexacto): the same rules and the same daily loop, rebuilt to run sharp and fullscreen on a Mac, with quality-of-life improvements, in-game tips, and two small extras: a lemonade stand that lives in the MacBook notch and a desktop widget for managing it at a glance.

## How the original content is handled

This repository holds only our own code and documentation. Players bring their own copy of the original installer; Lemonade Remixed unpacks it on their machine and uses its art and sound from there. Nothing from the original game is committed or distributed here.

- [tools/unpack_installer.py](tools/unpack_installer.py) unpacks the original Windows installer (`Setup.exe`) and checks every file against the CRC-32 the installer records.
- [docs/ORIGINAL.md](docs/ORIGINAL.md) explains how to run the original under Wine for reference.

## Documents

- [docs/MECHANICS.md](docs/MECHANICS.md): how the original game works, with the numbers measured so far.
- [docs/PLAN.md](docs/PLAN.md): what the remix adds and how it is built.

## Status

Research. The original runs under Wine on macOS, its catalogue and economy are documented, and the rebuild has not started yet.
