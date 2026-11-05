# Lemonade Remixed: plan

## Goal

The same game, made better in every way: the original rules and daily loop, sharp at any resolution and fullscreen, smoother, easier to read, and friendlier to play, plus a notch mode and a widget.

## Content

The remix runs on the player's own copy of the original installer. On first launch it asks for `Setup.exe`, unpacks it locally with the same method as [tools/unpack_installer.py](../tools/unpack_installer.py), and converts the art and sound from `Lemonade.RB` into its own cache. Enhanced art (cleanly upscaled or redrawn) is layered over the originals, so every sprite can be improved gradually without losing the original look. Decoding the `Lemonade.RB` format is the next research step.

## Improvements

**Look and feel**

- Fullscreen at any resolution, with the layout adapting to the window.
- Crisp pixel scaling of the original art, then enhanced sprites, smoother walking animations, and weather effects (rain, heat shimmer, clouds).
- Volume controls for music and effects, a mute button in the corner, and a keyboard shortcut (M). The notch and widget start muted.

**Quality of life**

- Speed controls: pause, 1×, 2×, 4× and skip day.
- Buy any number of packs in one go, with a single basket and no confirmation for every purchase.
- Saved recipes ("Hot day", "Rainy day") and optional restocking to target levels before each day.
- A clear end-of-day warning about melting ice, spoiling lemons and leftover lemonade.
- Customer feedback summarised: "6 found it too sour, 3 left because of the line".
- Charts for any period, autosave, undo for the day's setup, tooltips and full keyboard control.
- A local Highlights board replacing the defunct online one.

**Tips**

- An optional advisor gives one useful hint each morning, based on the forecast, your stock and yesterday's results ("It's 98 °F tomorrow: add ice, and a lemon to keep the taste").
- Customers' bubbles become readable hints you can open later.
- The original's business quotes stay on the menu.

**Notch mode**

The stand lives around the MacBook notch. Collapsed, it shows a tiny stand, today's weather and a running cup count beside the notch. On hover it expands into a small live view of the day with the essentials: price, recipe preset, start day and skip. Built as a borderless panel above the menu bar, positioned with the notch geometry macOS provides.

**Widget**

A desktop and Notification Centre widget that shows the stand, today's forecast, cash and yesterday's result. Interactive buttons (supported on macOS 14 and later) cover the morning routine: pick a recipe preset, nudge the price and start the day. The full game remains one click away.

## How it's built

- **One simulation core** written as a plain Swift package. Fixed rules, seeded randomness, no UI. The game, notch and widget all share it, and tests can replay whole careers to check the numbers against the original.
- **The game app** in SwiftUI with SpriteKit for the town view.
- **Notch and widget** as small front ends on the same core and save file.

## Steps

1. Decode `Lemonade.RB` (sprites, sounds, text) and build the importer.
2. Measure the remaining **open** numbers in [MECHANICS.md](MECHANICS.md): demand, satisfaction, popularity, advertising, staff and upgrade effects, and storage limits.
3. Build the simulation core and check it against recorded days from the original.
4. Build the fullscreen game on the core with the imported art.
5. Add the quality-of-life features, tips and sound controls.
6. Add notch mode, then the widget.
