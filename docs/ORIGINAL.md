# Running the original for reference

The original is a Windows program from 2002. It runs on macOS under Wine, which is how we measure its behaviour.

## The installer

The supported installer is the Zone.com edition of *Lemonade Tycoon Deluxe*:

| File | Size | SHA-256 |
|---|---|---|
| Setup.exe | 4,277,944 bytes | `9f3ee47922936b63e4940fddb6d83362e9d9e335b1b2ed81c5bc8dcdc7badead` |

It is a MindVision Installer VISE program whose archive sits in a PE section named `_mvdata`. Off-the-shelf VISE extractors handle installers that keep their data in separate files, not this one, so we read it ourselves:

```sh
python3 tools/unpack_installer.py Setup.exe game/
```

That writes nine files, each checked against its recorded size and CRC-32:

| File | Purpose |
|---|---|
| Lemonade.exe | the game |
| Lemonade.RB | resource bundle: art, sound and all game text |
| Lemonade.dat | 72-byte data file |
| Lemonade.ico | icon |
| fmod.dll | audio library |
| ArmAccess.dll | Armadillo trial protection |
| libmySQL.dll | the old online high-score service (offline now) |
| rapi.dll, ceutil.dll | Pocket PC save transfer |

## Running it in Wine

1. Create a dedicated prefix (`WINEPREFIX=... wineboot -i`) and copy the unpacked files into `C:\Program Files (x86)\Lemonade Tycoon Deluxe`.
2. Start `Lemonade.exe`. The Zone.com build opens Armadillo's trial reminder (60 minutes of play). **Enter Key** accepts the registration name and key supplied with the download; it is stored in the prefix and the limit goes away.
3. Sound can be turned off with the speaker button in the bottom-left corner of the game, or for a whole session by setting Wine's audio driver to none (`HKCU\Software\Wine\Drivers`, value `Audio` set to an empty string).

The game runs in a fixed 640 × 480 window.

## Automating it

Armadillo closes the game whenever another Windows process starts in the same Wine session. To script the game (for screenshots and measurements), start one long-lived helper first, let it launch the game, and send it commands; never start a new Wine process while the game runs. Inputs sent as window messages from inside Wine (mouse clicks at client coordinates, `WM_CHAR` for typing, `BM_CLICK` for dialog buttons) all work. macOS `screencapture -l <window id>` captures the game window alone.
