# Goals

Lemonade Remixed is built as a sequence of goals. Each goal has an objective, a test that says when it is done, and a loop to repeat until the test passes. Work on one goal at a time, keep its evidence (screenshots, logs, numbers) with the commit, and stop at the marked points that need Chris to play.

## The loop

1. **Pick** the first unfinished goal and its next unmet check.
2. **Change** the smallest thing that could meet it.
3. **Run** the real thing: build the app, launch the original through it, and drive it the way a player would.
4. **Measure** with evidence: captured frames of the app and the game, the helper's logs, timings.
5. **Compare** against the check. Pass: commit, tick it, go back to 1. Fail: note what was learned and go back to 2.
6. **Hand over** when a check needs hands-on play, a purchase or publishing; those are Chris's calls.

Rules that hold throughout:

- No original game files in the repository. Players bring their own `Setup.exe`.
- Never start a Windows process beside the running game; Armadillo closes it. Everything inside Wine goes through the one helper that launched the game.
- Builds, captures and scripted play are not acceptance. A goal that changes how the game looks or feels is done only after Chris has used it.

## Architecture

The original game keeps running, unchanged, in Wine. Lemonade Remixed is a native macOS shell around it:

- **Runtime**: Wine bundled inside the app, with a private prefix in `~/Library/Application Support/Lemonade Remixed`.
- **Helper** ([runtime/helper](../runtime/helper)): one Windows Python process inside Wine that launches the game and accepts input over a localhost socket (the bridge). Later it also reads game state and controls volume.
- **Presenter** ([mac](../mac)): takes the game's 640 × 480 frames and draws them wherever they're wanted (a window, fullscreen, the notch), and sends the mouse and keyboard back through the bridge.

## G0. The original runs and is understood ✅

- [x] Unpack the installer with checksum checks ([tools/unpack_installer.py](../tools/unpack_installer.py)).
- [x] Run the game in Wine, register it and automate it.
- [x] Document the catalogue and economy ([MECHANICS.md](MECHANICS.md)).

## G1. Prototype shell ✅

Proves the plumbing only: live frames from the Wine window via ScreenCaptureKit, input back over the bridge, and a panel at the notch.

Chris's first look (5 November) found the notch and picture not good enough: the strip wastes the space and shows unexplained crops, the expansion crams the whole desktop interface under the notch, the picture is soft, and the transition jerks. Those findings are now requirements in G3 to G5.

## G2. It just works

*Objective:* one app that takes a player from a fresh Mac to playing without ever seeing Wine.

- [ ] The app bundles Wine and creates its own prefix on first launch.
- [ ] First launch asks for `Setup.exe` (checking its SHA-256), unpacks it in Swift (a port of the Python unpacker) and installs the game into the prefix.
- [ ] The player enters their registration name and key in the app; the helper fills in Armadillo's dialog.
- [ ] Launch starts the helper, which starts the game; the presenter connects on its own and survives game restarts.
- [ ] The Wine window is never visible (kept off-screen or behind the presenter until G3 replaces capture with a frame tap).
- [ ] Mute works on every screen, and quitting the app closes the game and saves.

*Done when:* starting from an empty Application Support folder, choosing `Setup.exe` leads to the main menu in under a minute with no Wine window or dialog on screen, and saves survive a relaunch. Then Chris plays it.

## G3. A sharp picture

*Objective:* the original art looks crisp at every size, with no softness anywhere.

- [ ] Get exact game pixels. Today the frame is resampled twice: Wine draws the 640 × 480 window into a Retina window at double size, then ScreenCaptureKit scales it back down. Fix it with a frame tap: a small DLL loaded into the game (as a proxy for `msimg32.dll` or `fmod.dll`, both loaded from the game folder) copies each finished frame into shared memory. That also removes the screen-recording permission and lets the Wine window stay hidden. Interim: Wine's Retina mode with capture at native backing size.
- [ ] Scale only by whole numbers with nearest-neighbour sampling (2×, 3×, 4×), centring with a border instead of stretching to odd sizes.
- [ ] Add an optional smooth mode: a pixel-art upscaler (MMPX, xBR or ScaleFX, whichever has a licence that allows shipping) in a Metal renderer, so curves like the lemon's stay smooth at 4K.

*Done when:* a captured frame at 2× matches the game's own pixels exactly (each game pixel becomes a clean 2 × 2 block), fullscreen on the built-in display and a 4K monitor shows no blur, and Chris picks the default look from side-by-side captures.

## G4. Game state

*Objective:* the app knows what is happening in the game, so it can show real information instead of cropped pixels.

- [ ] The helper finds the game's values in memory (cash, date, time of day, weather and forecast, stock, price, recipe, cups sold today, popularity, satisfaction, current screen) and publishes them to the presenter about ten times a second.
- [ ] Volume: music and effects levels through the FMOD proxy DLL, replacing the speaker-button workaround.

*Done when:* every value matches the game screen over a full week, including across days, moves and purchases.

## G5. The game in the notch

*Objective:* a designed notch experience that uses the space well, makes sense at a glance and moves smoothly, built from the original art.

Collapsed (one strip, the full menu-bar height, using both sides of the notch):

- [ ] Left: the original stand sprite with customers queuing in real time (or the lemon when the stand is closed), and the day's progress.
- [ ] Right: today's cups sold and cash in a clean typeface, plus the weather icon from the game.
- [ ] Nothing that needs explaining: every item is labelled by its icon or obvious from context, and no raw crops of the game's interface.

Expanded (hover, or click to pin):

- [ ] Grows smoothly out of the notch like the Dynamic Island: one panel whose shape animates with a spring and whose contents fade in, never a resized window.
- [ ] A clean layout designed for the notch: the live town view with the stand as the hero image, today's numbers, and a few large controls (start day, skip, price, recipe preset, mute).
- [ ] "Open full game" reveals the complete original interface at a whole-number scale for planning screens (supplies, upgrades, rent).

Behaviour:

- [ ] The game keeps running while collapsed, and the info stays live.
- [ ] Works without a notch (a pill at the top centre), across Spaces, above fullscreen apps and on multiple displays.

*Done when:* a whole in-game week can be played from the notch and Chris signs off on the look and motion after a working session.

## G6. HD art

*Objective:* individual sprites, starting with the lemon, replaced by upscaled versions while everything else stays original.

- [ ] Decode `Lemonade.RB`: list its entries, export every bitmap and sound, and document the format.
- [ ] An HD art pack (sprite ID to PNG at 4×) and a pipeline that upscales sprites with an AI upscaler plus hand touch-ups. The pack stays outside the repository because it is derived from the original art; players generate or install it locally.
- [ ] Fixed interface first: the top-bar icons, tab buttons, logo and panels always sit in the same place, so the presenter draws the HD version wherever it finds the original pixels.
- [ ] Moving sprites next (customers, the stand, weather): the in-game DLL records each blit (source bitmap and destination) and the presenter draws the matching HD sprite in its place.

*Done when:* the interface and then the town view render in HD with exact placement and no flicker, and Chris approves the look.

## G7. Tips and quality of life

*Objective:* help without changing the game's rules.

- [ ] A morning advisor: one tip from the forecast, stock and yesterday's results, shown in the notch and the window.
- [ ] Shortcuts that click through the original interface: buy several packs at once, apply a saved recipe, restock to targets.
- [ ] An end-of-day summary: melted ice, spoiled lemons, leftover lemonade and why customers left.

*Done when:* each shortcut produces exactly the same game state as doing it by hand (checked with G4), and Chris has played with them.

## G8. Widget

- [ ] A WidgetKit widget showing the stand, forecast, cash and yesterday's result.
- [ ] Buttons (macOS 14 and later) for start day, a recipe preset and price up or down, routed to the running app.

*Done when:* a whole morning routine can be done from the widget.

## G9. Ship

- [ ] A signed app with Wine bundled (LGPL, with its source offered), a player README covering where to get their own installer, and a release checklist.
- [ ] A clean-machine check, like PadMint's player check: a fresh user account with no developer tools, just the app and `Setup.exe`.
- [ ] Publishing is Chris's decision.

## Fallback

If running the original ever blocks a goal (Armadillo, Wine regressions, art that can't be swapped cleanly), the documented mechanics allow a full rebuild that uses the same decoded art. That is a larger project and is not the plan.
