# Porting plan: a native engine for Mac, iPhone and iPad

Today Lemonade Remixed runs the original Windows game, unchanged, inside a copy
of Wine bundled in the app. That is what makes it install in seconds and play
exactly like the original, and it is why it only runs on the Mac. This document
is the plan for the next step: a native engine, written in Swift, that plays
the same game with the player's own art and sound, on macOS, iOS and iPadOS.

Nothing here replaces the current app until the new engine matches it.

## Why

- **iPhone and iPad.** Wine can't run on iOS (apps there may not generate code
  at run time), so the original's Windows code can't run there at all.
- **macOS 28.** The bundled Wine is Intel code that runs through Rosetta 2,
  which Apple scales back after macOS 27 ([G10](GOALS.md#g10-ship)).
- **A real download.** Without Wine, a signed app is smaller, simpler to
  notarize, and has no LGPL source obligations for a bundled runtime.

## What stays the same

- **Bring your own copy.** Players still supply `Setup.exe`. The installer
  unpacker (`RemixCore.InstallerArchive`) is already pure Swift, so it runs on
  iOS unchanged (import `Setup.exe` from the Files app). No game files ship.
- **The original art and sound**, decoded from the player's copy.
- **Everything around the game**: the notch, the Advisor, restock, saved
  recipes and settings already work from a `GameState`; they would read it
  from the new engine instead of from the original's memory.

## The work

| Phase | What | Size | Main risk |
|---|---|---|---|
| P1. Assets | Decode `Lemonade.RB` (the archive holding every sprite, sound and font) into images and sounds the app can load, on the player's machine. Document the format. Same first step as [G6](GOALS.md#g6-hd-art-parked). | Days | An unknown or compressed format. |
| P2. Rules | The simulation in Swift: weather and forecast, the calendar and news, stock and spoilage (ice melts, lemons rot), recipes and pitchers, prices, rent and locations, upgrades, staff and ads, popularity and satisfaction, the reports. Much is measured already in [MECHANICS.md](MECHANICS.md) and [STATE.md](STATE.md). | 1–2 weeks | The customer model (how many come, what they'll pay, what pleases them) is only partly measured. |
| P3. Matching | Run the original and the new engine side by side through the existing bridge: same start, same choices, compare cups sold, cash, popularity and satisfaction day by day, and tune until they agree. This is what makes it *the same game*. | 1–2 weeks | Randomness: matching averages over many days rather than every customer. |
| P4. Screens | Draw the isometric town with customers walking up and reacting, and rebuild the planning screens and menus from the decoded art, in SpriteKit or Metal. | 1–2 weeks | Many screens; the feel of movement and timing. |
| P5. Mac | Swap the engine under the existing app behind a setting; keep the Wine path until the new one has been played for a while. | Days | |
| P6. iPhone and iPad | A SwiftUI app around the same engine: touch, any window size on iPad, Files import of `Setup.exe`, the iOS icon. [G11](GOALS.md#g11-iphone-and-ipad-plan-only-in-parallel-with-the-notch) | 1 week | |

Roughly five to eight weeks of focused work in total, most of it in P2 to P4.
The order matters: P1 is cheap and shows quickly whether the art can be used
cleanly, and P3 is what keeps the port honest.

## First steps

1. Decode `Lemonade.RB` and list its contents (P1).
2. Measure the customer model: play controlled days in the original through the
   bridge, varying one thing at a time (price, temperature, popularity), and
   record visitors and sales. This fills the open questions in MECHANICS.md.
3. A prototype in the iOS simulator: the decoded town view with the cart and a
   few walking customers, to prove the drawing approach.
