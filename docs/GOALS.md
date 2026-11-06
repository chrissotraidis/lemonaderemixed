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

## G2. It just works ✅

*Objective:* one app that takes a player from a fresh Mac to playing without ever seeing Wine.

- [x] The app bundles Wine and creates its own prefix on first launch (`wineboot` runs with the Mac display driver off, so Wine's "updating" dialog can't appear).
- [x] First launch asks for `Setup.exe`, checks its SHA-256 and unpacks it in Swift (`RemixCore.InstallerArchive`; byte-identical to the Python unpacker) into the prefix.
- [x] The player enters their registration name and key in the app; the helper fills in Armadillo's dialog. A wrong key shows an error and can be retried.
- [x] Launch starts the helper, which starts the game; the presenter connects on its own. The app quits when the game closes, and a relaunch reconnects.
- [x] The Wine window is never visible (G2 kept it off-screen; G3 replaced that with a headless display).
- [x] Mute works on every screen: an FMOD proxy (`runtime/fmodproxy`) applies the app's volume to FMOD's effects master, which carries every sound the game plays (it never uses FMUSIC). Measured: master volume 0 while muted.
- [x] Quitting the app closes the game and every Wine process; saves survive (supplies and day progress checked across two relaunches).

*Done when:* starting from an empty Application Support folder, choosing `Setup.exe` leads to the main menu in under a minute with no Wine window or dialog on screen, and saves survive a relaunch. Measured on 5 November: 21 seconds, no Wine window, saves intact. Chris played it on 5 November: it works.

## G3. A sharp picture ✅

*Objective:* the original art looks crisp at every size, with no softness anywhere, and Wine stays invisible.

- [x] Exact game pixels from a frame tap. The in-game agent (`runtime/agent`, loaded by the game in place of `fmod.dll`) copies each finished 640 × 480 frame into a shared, double-buffered file (`remix-frames.bin`) about 60 times a second, and the app reads it directly. No screen capture or screen-recording permission is involved.
- [x] Wine is invisible: with frames coming from the tap, Wine uses its headless display driver, so the game's windows are never shown and Wine never appears in the Dock or app switcher (checked from install to play: zero foreground Wine processes, zero on-screen Wine windows).
- [x] Wine gets a private home folder, and its Desktop, Documents and similar folders are plain folders inside the app's setup, so macOS never asks for access to the player's files.
- [x] Sharp mode (default) fills the window with crisp pixels at any size: inside each game pixel the colour is flat, and only the one screen pixel at its edge blends into the neighbour. At whole-number sizes it is exact.
- [x] Pixel-Perfect mode (⌘2) keeps whole-number scaling with a border, for exact square pixels.
- [x] Smoothing was tried (MetalFX) and dropped: it softens the pixel art.
- [x] A high-resolution app icon (a lemonade glass in front of a striped stand, our own art) in every macOS size; an iOS master is saved alongside for G10.

*Done when:* the picture fills the window without blur at whole and fractional sizes (measured at 3× and 3.44×), and Chris approves the look. Higher-resolution art itself comes in G6.

## G4. Game state ✅

- [x] The helper reads cash, price, recipe, stock, day, the three-period forecast and live temperatures, location and rent, today's sales/profit/missed, and the last day's report (revenue, stock used and lost, rent, ads, earnings, walk-aways, melted ice) from fixed addresses in the game ([STATE.md](STATE.md)), plus the current screen from the frame. The bridge's `info` command returns it as JSON; the app polls it twice a second.
- [x] Checked against the game's own screens over nine scripted days, including a move to the Park, purchases and recipe changes.
- [x] Popularity and satisfaction for the current location (6 November; [STATE.md](STATE.md)), shown as game-style meters in the notch's planner and in the full game's header line.
- [ ] Still unmapped: upgrades and staff owned, advertising.
- [ ] Volume levels beyond mute (music/effects sliders) through the in-game agent.

## G5. The game in the notch (second version built, waiting for Chris)

*Objective:* the stand lives in the notch while you work. You glance at it for status, open a live street view with speed controls, and open the whole game when you want to play.

Three states, and the game keeps running in all of them:

- [x] **Island** (collapsed): black wings on both sides of the notch at full menu-bar height. Left: a fast-forward toggle while selling (yellow when on; on this side because the right is often full of other apps' icons), cash in the game's yellow, a status line and a live crop of your cart. While idle the status line takes turns (day, forecast, cups ready or "restock needed", "click to plan"), and on the main menu the icon rocks gently beside "click to play". Right: the temperature, if there is room. The right wing measures the free menu-bar space every 3 seconds and never covers other apps' icons.
- [x] **Small view** (mini, 600 points wide), playable for the everyday loop:
  - *Selling:* the live street around your cart at 2×, clean of overlays; the numbers move into the notch's wings (cash, profit today, sold, walk-aways). Hide, Sound, Skip day, Fast, Full game.
  - *Planning:* one view, no switching (compared with a Quick/Menus toggle on 5 November and chosen over it). Left: your cart and a game-green planner with the forecast and rent, recipe and price steppers (sent to the game when the clicking stops), Restock with its price when short, a plain result line ("Bought 48 lemons for $9.60"), saved recipes and the Advisor's top tip. Right: the game's own stock bar, seven tabs and panel at 1×, live and clickable, so rent, upgrades, staff, marketing, recipe, supplies and results all work from the notch with the original art (checked: an upgrade bought from here).
  - *A question from the game:* the middle of the screen at 1×, clickable, so it can be answered in place. *Main menu:* the whole screen, with a note to start or load in the full game.
- [x] One place at a time: opening the notch hides the game window, and showing the window (Dock, ⌘0, the full game's Window button) tucks the notch back into its island. The Advisor button shows only while planning, so it never covers the game's day panel.
- [x] Settings (⌘,) in the game's look: notch on or off (on by default), sound (mute, 25 to 100%), picture (Sharp or Pixel-Perfect) and where to get the game. Turning the notch off brings the window back instead of leaving the app with nowhere to show the game.
- [x] Start day from the notch: with nothing to sell it says "Not enough supplies for a single cup. Restock first." instead of pressing the game's button; if the game still objects, its message shows in the small view at once and can be answered there.
- [x] **Full game**: the whole game at 1×, playable, in the game's green with a header showing the day, the weather and today's sales, plus Fast, Sound, Window (move to its own window) and Shrink.
- [x] Clicking the notch toggles island ↔ street view (from the full game, back to the street view). Clicking anywhere else, or Esc, shrinks the full game to the street view, which stays open while you work. Transitions take 0.16 s.
- [ ] Chris's verdict on the island's right wing (what it should show) and on the street view's smoothness.
- [ ] The yellow pulse at day end, checked on screen.
- [x] Without a notch: a pill at the top centre, the same two halves meeting with no gap, the same lemon outline and the same small view hanging from it. Checked with `LEMONADE_PILL=1` (it lays out as on a Mac without a notch) on 6 November; not yet seen on a real notchless Mac or an external display.
- [ ] Across Spaces and over fullscreen apps, checked on screen.
- [x] Popularity and satisfaction mapped and shown (the planner's meters; satisfaction turns orange under 50%).

*Done when:* a full in-game week can be played from the notch, then Chris uses it for a working session.

## G6. HD art (parked)

Parked on 5 November: the original art looks good drawn sharp, and upscaling hundreds of sprites is the costliest, least certain item. A cheap test (top-bar icons, tabs, logo) stays possible later.

### Original plan

*Objective:* individual sprites, starting with the lemon, replaced by upscaled versions while everything else stays original.

- [ ] Decode `Lemonade.RB`: list its entries, export every bitmap and sound, and document the format.
- [ ] An HD art pack (sprite ID to PNG at 4×) and a pipeline that upscales sprites with an AI upscaler plus hand touch-ups. The pack stays outside the repository because it is derived from the original art; players generate or install it locally.
- [ ] Fixed interface first: the top-bar icons, tab buttons, logo and panels always sit in the same place, so the presenter draws the HD version wherever it finds the original pixels.
- [ ] Moving sprites next (customers, the stand, weather): the in-game DLL records each blit (source bitmap and destination) and the presenter draws the matching HD sprite in its place.

*Done when:* the interface and then the town view render in HD with exact placement and no flicker, and Chris approves the look.

## G7. Advisor and quality of life ✅

The Advisor is a game-style button beside the game's speaker; it opens over the game's left panel like another tab and has a dot when there's a new report or an urgent tip. Chris approved the look on 5 November; it starts closed.

- [x] Morning tips from the forecast, stock and yesterday's report (ice for heat, price for sun or rain, restock warnings, walk-aways, melting ice, rent pressure). While a day runs it shows live cups, profit and walk-aways.
- [x] Day report: the game's own numbers for the last day, until dismissed.
- [x] Saved recipes: save today's recipe and price (named after the weather), apply on any day with one click.
- [x] One-click restock: the cheapest packs that cover a target number of cups for the current recipe.
- [x] Multi-pack buying: a basket of any packs bought in one go; the game's confirmation is turned off the first time.
- [x] Every action clicks through the original interface and is checked in memory (buy, recipe and price verified exactly).

## G8. Bring your own game ✅

- [x] First run explains that Lemonade Remixed doesn't include or provide the game, links to the abandonware archives (Old Games Download, the supported Zone.com edition; My Abandonware), and asks for Setup.exe. A wrong file gets a clear message.
- [x] Help ▸ Where to Get the Game and the About box repeat it, with Wine and font licences.

## G9. Widget

- [ ] A WidgetKit widget showing the stand, forecast, cash and yesterday's result.
- [ ] Buttons (macOS 14 and later) for start day, a recipe preset and price up or down, routed to the running app.

*Done when:* a whole morning routine can be done from the widget.

## G10. Ship

- [ ] A signed app with Wine bundled (LGPL, with its source offered), a player README covering where to get their own installer, and a release checklist.
- [ ] A clean-machine check, like PadMint's player check: a fresh user account with no developer tools, just the app and `Setup.exe`.
- [ ] **macOS 28 and Rosetta.** The app is native arm64, but the bundled Wine (Wine Stable 9.0, 183 x86_64 binaries) runs through Rosetta 2, so macOS shows "Support Ending for Intel-based Apps". Apple keeps full Rosetta through macOS 27 and only a games-oriented subset after; whether Wine qualifies is unannounced. Before shipping: test on the macOS 28 beta, and switch `bundle.sh` to a native arm64 Wine (with its x86 translation layer) once one is usable on macOS. Nothing else in the app depends on how Wine is built. If none arrives in time, the Fallback below applies.
- [ ] Publishing is Chris's decision.

## G11. iPhone and iPad (plan only, in parallel with the notch)

*Objective:* a plan, proven in the simulator, for Lemonade Remixed on iOS and iPadOS as a resizable app.

- [ ] Decide how the original runs there. Wine can't run on iOS (no JIT for third-party apps), so the candidates are an x86 interpreter with a small Win32 layer for the handful of GDI/USER/FMOD calls this game makes, or a rebuild of the rules from MECHANICS.md and STATE.md drawing the player's decoded art. Prototype the cheaper one in the simulator first.
- [ ] Reuse RemixCore (state, advisor, restock, saved recipes) and the themed SwiftUI assistant unchanged.
- [ ] Touch controls, any window size on iPad (Stage Manager, Split View), and the iOS icon (master in `mac/Resources/icon`).

*Done when:* the plan is written with a simulator prototype as evidence.

## Fallback

If running the original ever blocks a goal (Armadillo, Wine regressions, art that can't be swapped cleanly), the documented mechanics allow a full rebuild that uses the same decoded art. That is a larger project and is not the plan.
