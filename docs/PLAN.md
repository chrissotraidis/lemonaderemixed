# Lemonade Remixed: plan

## Goal

The original *Lemonade Tycoon Deluxe*, untouched, running inside a native Mac app that makes it better: sharp and fullscreen at any resolution, upscaled art, sound controls, tips and shortcuts, playable from the MacBook notch, and a desktop widget for managing the stand.

## Approach

The game runs unchanged under Wine from the player's own installer. Our app takes its frames, presents them (in a window, fullscreen or the notch) and sends input back. All the original art, sound, rules and quirks are there because it really is the original; the improvements sit around it. HD art replaces individual sprites as they're drawn, starting with the lemon.

The work is organised as goals with clear tests in [GOALS.md](GOALS.md). How the game works is documented in [MECHANICS.md](MECHANICS.md).

## What players get

- **The real game**, with its saves, modes and look.
- **A sharp picture** at any size and in fullscreen: original pixels, smooth upscaling or HD art.
- **Notch mode**: the stand and today's numbers beside the notch; hover to open a clean view of the day with the main controls. The game keeps running while it's collapsed, and mute is one click.
- **Widget**: the stand, forecast, cash and yesterday's result, with buttons for the morning routine.
- **Help**: a morning tip, readable customer feedback, shortcuts that do several clicks at once, and a clear end-of-day summary.
- **Sound controls**: mute, then separate music and effects volume.
