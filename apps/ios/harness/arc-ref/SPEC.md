# Arc Search (iPhone UI): measured reference

Captured 2026-11-21 from **Arc Search 1.49.0 (88824.2)** on an iPad Air 11" (M4), iPadOS 27.2.1, in a
resizable window set to **401 × 878 pt** (target was 402 × 874 pt, the iPhone 17 Pro; the window snaps
in ~2 pt steps). The system was in dark mode. Raw media (full-res PNGs, 60 fps H.264 streams with
per-frame host timestamps, input logs) is in `apps/ios/harness/runs/arc-ref/` (git-ignored). The
downscaled stills here are in `shots/`.

> **Caveats, read first**
> - **Not checked against a real iPhone.** No iPhone recording of Arc was available for this pass.
> - Arc Search on iPad doesn't change layout with window width. Full screen (820 pt) shows the same
>   single-column phone UI: the same three-slot bottom bar, + capsule and ^ circle (`runs/arc-ref/s00_start.png`).
>   At 401 pt every control below has phone-sized metrics, so this is the iPhone layout. But two
>   iPhone-specific things can't be seen here:
>   1. **No home-indicator inset.** The bar sits flush with the window bottom (its bottom ≈ 28.5 pt below
>      the button centre line). On an iPhone the bar probably sits ~34 pt higher, or grows by that much.
>   2. **No status bar.** Pages draw from y = 0 under the window's ••• control. Every *y* value below is
>      from the window top. Cards and the bar are centred or bottom-anchored, so prefer the
>      bottom-relative and centre-relative numbers.
> - The keyboard is the iPad's full-width floating keyboard, so **nothing here says how the search
>   panel rides an iPhone keyboard.**
> - The session ended early: CoreDevice stopped answering (`devicectl` lock-state and display queries
>   time out) while session 3 started. Bar swipes, swipe-up, flick-to-close, search typing and dismiss,
>   menu timing, scroll video and edge-swipe were **not captured**. See "Not measured".

Units are points (pt); the device is 2×, so 1 pt = 2 px in the raw PNGs. Coordinates are
**window-local**: x from the window's left edge, y from its top. The window is 401 × 878 pt.

## 1. Layout

### 1.1 Bottom bar on a page (`shots/01-page-light-bar.png`, `02-page-dark-bar.png`, `z-bar-*-2x.png`; measured on `runs/full_06_tabs8.png`)

| Element | Measured | Notes |
|---|---|---|
| Bar band | y 825.5 → 878, **52.5 pt** tall, full width | No hairline. Above it, a soft fade ~25 pt tall (page #fff → #f1f1f1 at the bar's top edge on light pages; #08080a → #1c1d1e on dark ones). |
| Button centre line | y **849.5–849.75** | 24 pt below the bar's top and 28.5 pt above the window bottom |
| Tabs button (left) | Stack of 2 thumbnails, cluster x ≈ 24.5–65; front card ≈ **28 × 29 pt**, rotated **≈ +8°**, corner radius ≈ 4; back card rotated **≈ −18°**, partly hidden | The front thumbnail is the **previous** tab (n−1), not the current one; the back one is n−2 (`z-tabs-thumbnail-grid.png`) |
| + button (centre) | Capsule x 163 → 238.5 (**75.5 pt**), y 829.75 → 869.25 (**39.5 pt**), radius = half height (19.75) | Centred (200.75 vs window centre 200.5). The + glyph is ≈ 16.5 pt tall, stroke ≈ 2 pt. |
| ^ button (right) | Circle, diameter **33.5 pt**, centre (360.75, 849.75), x 344–377.5 | Right margin 23.5 pt; left margin to the thumbnail cluster ≈ 24.5 pt |
| Bar after scrolling down | **Hidden completely**; the page fills the window (`03-bar-hidden-after-scroll-down.png`) | Scrolling back up brings it back (`04-…`). The thin grey line in shot 03 is the page's own horizontal scrollbar (desktop Wikipedia), not Arc. |

Bar colours, sampled at x = 120 (hex):

| | Bar top (y 827) | Bar middle (y 850) | Bar bottom (y 872) | + capsule | ^ circle | Glyphs |
|---|---|---|---|---|---|---|
| Light page (white) | `#e5e5e5` | `#d5d5d5` | `#c7c7c7` | `#bdbdbe` | `#c3c3c4` | `#2f2f2f` |
| Dark page (#08080a) | `#2f3030` | `#3a3b3b` | `#444444` | `#535454` | `#4e4f50` | `#ffffff` |

Solving the two backgrounds together gives a grey overlay (~`#8c8c8c`–`#9c9c9c`) whose alpha
ramps from **≈0.26 at the top to ≈0.47 at the bottom**. The capsule and circle are a further
≈0.3-alpha mid-grey (~`#898989`) on top: darker than the bar on light pages, lighter on dark ones.
It reads as a translucent material, probably blurred. A uniform page can't show the blur.

### 1.2 Tab switcher (`05-switcher-opened.png`, `06-switcher-deck-end.png`, `07-…`, `08-…`, `16-…`, grid zooms `z-card-header-grid.png`, `z-switcher-stack-grid.png`)

It is a **horizontal, overlapping card deck**, not a grid. Order is by recency: the newest tab is
rightmost and sits **on top**, and older cards stack under it to the left. One finger scrolls it
sideways.

| Item | Measured | Source |
|---|---|---|
| Card size | **281 × 607 pt** (= 0.70 × window width, 0.691 × window height; aspect 0.463 vs the window's 0.457) | `full_27c.png`, newest card fully visible |
| Card vertical position | top 135, bottom 742, centre 438.5 = window centre (439) | 27c and 26 |
| Corner radius | **≈ 24 pt**; the profile fits a circle of r = 24 to ±0.5 pt, maybe continuous-curvature | profile fit on 27c |
| Tilt or rotation | **none** (edges vertical to within 0.5 pt over 600 pt) | 27c |
| Depth on older cards | Each step left: smaller and lower, dimmed | `full_26.png` |
| Slots in the opened state (from a page) | **current (n)**: left 308–309, top 134, h 610 (scale ≈ 1.005), cut off by the window's right edge, ~92 pt visible · **n−1**: left 84, top 135, h 607 (1.0), with title · **n−2**: left ≈ 13, top ≈ 148, h ≈ 589 (≈ 0.97), header dimmed ≈ 40 % · **n−3**: left ≤ 0, top ≈ 160, h ≈ 557 (≈ 0.92), dimmed ≈ 40 % | 26 / 13 / 07b |
| Horizontal spacing | n → n−1: **224 pt**; n−1 → n−2: ≈ 71 pt; then ≈ 13 pt and less (strongly compressed) | 26 |
| Deck scrolled to its end | The newest card is centred (left 60.5, right 341.5); n−1's header peeks at x ≈ 30 | 27c |
| Card header (above each card) | **Favicon 20 × 20 pt**, radius ≈ 4, left = card left + 18, top = card top − 28 (y 107–127). **Title** starts 7 pt right of the favicon (card left + 44.5), cap height 8.5 pt → **≈ 12–13 pt**, medium weight, white, one line with an ellipsis, vertically centred on the favicon | 27c (`Penguin – Wikipedia`), 26 (`Linear – The system for product…`) |
| When a title shows | Only while there's room before the next card's favicon. The covered card n−1 shows favicon only, and n (right edge) shows favicon only. | 26, 27c |
| Background | Near-uniform dark navy: `#1b1b2d` top centre, `#1d1c2d`–`#201e2f` top corners, `#242432`/`#26212c` near the bottom (system dark mode; light mode not tested) | 27c |
| Switcher bottom bar | Same 3-slot geometry, no bar band. Left: **circle 33.5 pt** at centre (40.75, 850) with a desktop icon (Arc Desktop sync); centre: the same **75.5 × 39.5 + capsule**; right: **circle 33.5 pt** at (360.75, 850) with a gear (Settings). Fills: circles `#3f3f4a`, capsule `#3a3a48`, glyphs white. | `z-switcher-bar-grid.png` |
| First open | Tooltip above the left circle: "Every tab, anywhere. / Sync with Arc Desktop" with an X | `08-switcher-first-open-sync-tip.png` |

### 1.3 Search panel, empty (`09-search-panel-empty-ipad-keyboard.png`, `z-search-grid.png`)

Tapping + opens a sheet over the current page, which stays visible. There is no separate
new-tab page.

| Item | Measured |
|---|---|
| Panel top | y ≈ 541 with the iPad keyboard up; top corner radius ≈ 30 pt; dark translucent (`#2b2b2b`-ish over the page) |
| Field | Capsule x 16 → 385 (**369 × 47.5 pt**); "Search…" placeholder ≈ 17 pt at x 41; a caret appears at once (Auto-Open Keyboard is on by default). Right of it: mic icon (x ≈ 311) and the "Browse for Me" eyes icon (x ≈ 356). |
| Suggestion rows | Magnifier at x ≈ 29, text at x 49, ≈ 17 pt; rows ≈ 56 pt apart (centres 640, 696); "Browse for Me" pill right-aligned, x 284–384, ≈ 30 pt tall |
| Keyboard | The iPad's floating full-width keyboard, top at screen y ≈ 845 (window y ≈ 744). It covers the window's bottom; the panel does not move above it here. |

The panel while typing wasn't captured (the session ended first).

### 1.4 Page menu (^ button) (`10-page-menu.png`, `z-menu-grid.png`)

| Item | Measured |
|---|---|
| Sheet | Full width, top y ≈ 479.5, top radius ≈ 30, reaches the window bottom; a **light** material over a light page (`#ececed`), and the page behind dims (white → `#cccccc`) |
| Insets | 16 pt sides |
| Address row | Capsule 369 × 47.5 (y 495–542.5): back `<` (x ≈ 42) and forward `>` (x ≈ 81) on the left, domain `en.wikipedia.org` centred (~17 pt, semibold), link (x ≈ 321) and reload (x ≈ 359) on the right; fill `#d6d7d9` |
| Action tiles | 4 tiles, **80 × 80 pt**, radius ≈ 20, x 16 / 113 / 209 / 305 (gap ≈ 16.5), y 559.5–639.5; labels below (Find on Page, Summarize, Pin, Share), ≈ 14 pt grey, baseline ≈ 660; fill `#d2d3d4` |
| List rows | Display Options (›) y 678–725.5; Site Settings y 742–789.5; "Arc scrubbed 1 tracker / Problems? Tap to restore original page" y 805–860; each 369 wide, ≈ 47.5 tall (the tracker row is 2 lines), radius ≈ 16, gap ≈ 17 |
| Dismiss | Tapping the dimmed page closes it (seen; not timed) |

### 1.5 Settings, Archive and auto-archive (`11-…` to `14-…`)

- **Gear** in the switcher bar → Settings sheet (`#29292a`; title "Settings", a "Done" capsule at the
  top right). Top row: two 47 pt buttons, **Downloads** and **Archive** (`#434344`). Then grouped
  lists: Global Site Settings · Set Arc as Default Browser / Change App Icon / Add to Home Screen ·
  Search Engine (Google) / Languages · Auto-Open Keyboard (on) / **Archive Inactive Tabs (After 1 day)** /
  Open App Links in… (Native App) / Clear Browsing Data… / Export Data · Sync with Arc Desktop ·
  Gift Arc · Contact / Show Onboarding / Privacy / Licenses.
- **Archive Inactive Tabs** opens a popup menu: **12 hours · 1 day (default, checked) · 3 days · 7 days ·
  30 days** (`13-archive-interval-picker.png`). This is the only tab-lifetime setting.
- **Archive** sheet (`#1c1c1d`, a violet `#7b8df7` ✓ close button): empty state "Nothing here yet! /
  Manually closed and auto-archived tabs will appear here." Closing a tab archives it rather than
  deleting it.

### 1.6 Start page, Incognito

- **Start page**: this install's first tab is Arc's "A farewell to Arc" page (`15-start-page-farewell.png`;
  bg `#0b0b0b`). There's no separate new-tab page: + always opens the search panel (1.3).
- **Incognito: no entry point found.** I checked the switcher bar, the Settings sheet, the page menu,
  a long-press on + (that's voice search) and a long-press on the tabs button (nothing happens). I
  found no private or incognito mode in 1.49.0.

## 2. Motion

### 2.1 Method and uncertainty

- **Video**: `axe stream-video --format h264`, the device's native 60 fps stream (1648 × 2368). It sends
  frames on change (~60 fps in motion, ~20 fps idle). A recorder stamped each received chunk with host
  time, and an Annex-B parser maps each frame to the chunk that completed it. Inputs were sent by a
  runner that logs host time before and after each `axe` command. Frames were diffed at 1/4 scale over
  the window crop, and geometry was tracked at 1 pt (edge of a white or dark card).
- **Clock uncertainty**:
  - Frame arrival times jitter **±8 ms** (gaps of 14–29 ms between frames in a steady 60 fps run). Treat
    durations as **±1 frame (17 ms)**.
  - Times are from the **AXe command start**, which includes AXe's own input latency and the stream
    latency. Those can't be separated without a reference clock.
  - The fastest touch-down response seen (card press feedback) arrived **86–105 ms** after command
    start, so the rig floor is ~70–100 ms. Arc itself answered within ~1 frame of each touch phase:
    AXe's `tap` holds ~50 ms, and every control showed a touch-down change and then a touch-up change
    about that far apart.
  - Durations below are measured **from the last static frame**, so the rig latency doesn't affect them.
- **Curve fits**: a damped-spring model (start, ω, ζ) and an exponential ease-out, by least squares on
  normalized progress. *Response* = 2π/ω (SwiftUI's term).

### 2.2 Per-transition table

Durations are from the last static frame. *Settle* is the last frame that moves more than 0.6 pt.

| Transition (sample) | Touch phase that triggers it | Command → first frame | 50 % | 90 % | 99 % | Settle | Curve | Source |
|---|---|---|---|---|---|---|---|---|
| **Tabs button → switcher**, current page → right slot (n=3) | touch-up | 162–195 ms (rig) | 55–64 ms | **118–134 ms** | 204–221 ms | **252–305 ms** | **critically damped spring, ζ = 1.00, response 189–196 ms**, no overshoot (rms 0.004–0.005) | `s1` tabs_open_1/2, `s2` r3/r5_tabs; frames `v-switcher-open-frames.jpg` |
| ↳ previous tab's card flying out of the tabs thumbnail into slot n−1 | same moment | same frame as above | ≈ 97 ms | **≈ 203 ms** | ≈ 323 ms | **≈ 482 ms** | critically damped, **response ≈ 279 ms** (slower than the main card), no overshoot | `s1` tabs_open_1 (card top 769 → 107 pt) |
| ↳ bar icons swap (^ → gear, thumbnail → desktop) | same moment | same frame | — | **2 frames (~30 ms)** | | ≈ 50 ms | crossfade | ROI on the right button, `s1` |
| **Card → page** (zoom to full window) (n=3) | touch-up | 132–160 ms (rig); ≈ 45–55 ms after the touch-down feedback frame | 65–80 ms | **155–166 ms** | 264–329 ms | **287–347 ms** | **critically damped, ζ = 1.00, response 256–272 ms**, no overshoot (rms 0.006–0.012) | `s1` card_prev_1, card_cur_2, open_penguin_from_deck_end |
| Card press feedback | **touch-down** | 86–105 ms (rig floor) | | | | | the card shrinks ≈ 0.5 % (top edge +1.5 pt, left +0.5 pt) and holds until release | `s2` r4_card_hold_025 |
| Bar button press highlight (tabs, +) | **touch-down** | 115–134 ms | | | | ramps ≈ 170 ms to full | ease-out brighten of the button | ROI, `s1` tabs_hold_1s, plus_hold_03 |
| Bar button release | touch-up | | | | | fades ≈ 70 ms | | `s1` plus_hold_03 |
| **+ held ≥ 0.3 s** | long press | | | | | bar morphs into a blue "Speech and Mic permissions required" banner in ≈ 120 ms | voice search, not the search panel | `s1` plus_hold_03, `runs/vid/sh_search.png` |
| **Tabs button held 1 s** | — | | | | | highlight shows, **auto-cancels ≈ 500 ms into the hold** (fades ~230 ms), and **nothing opens on release** | | `s1` tabs_hold_1s |

Exponential fits to the same curves give τ ≈ 47–48 ms (switcher open) and τ ≈ 64–69 ms (card open).
Late in the motion the remaining distance shrinks by ×0.65 per frame (switcher open). As a
starting point to match: **switcher open: spring response ≈ 0.19 s, damping 1.0; card zoom: spring
response ≈ 0.26 s, damping 1.0; the n−1 card flying out of the thumbnail: response ≈ 0.28 s, damping
1.0.** Nothing overshoots.

### 2.3 Interruption (`s2`, frames in `v-tap-during-open-cancels.jpg`, `v-tabs-during-zoom.jpg`)

| Test | What happened | Numbers |
|---|---|---|
| Tap on a card **while the switcher is opening** (r1, the tap landed ~70–100 ms into the open, on the n−1 card) | **Cancelled.** The open reversed from its current position and zoomed back into the **current** tab. The card under the finger was **not** selected. The thumbnail card flew back into the tabs button. | The current card's left edge rose to 296 pt, then turned on the next frame after the tap: 296 → 263 → … → 1 pt in ~350 ms |
| **Tabs ↔ card ↔ tabs ↔ card**, ~100 ms apart (r2) | Every tap was accepted and **reversed the motion on the next frame**, from where it was. No sign that momentum carried over (no frames continuing in the old direction). | 1 → 229 → 83 → 257 → 1 pt; each reversal ~155 ms after its command start, the same as a normal tap's response |
| **Tabs tapped while a card is zooming open** (r3: 154 ms after the card tap, zoom ~86 % done; r5: 302 ms after, zoom finished) | Accepted at once. The page shrank straight back into the switcher, and the tab just opened became current (rightmost). Nothing waits for the zoom to finish. | Turnaround 156 ms (r3) and 153 ms (r5) after the tabs command, the same as from rest |
| Hold a card 0.25 s in the switcher (r4) | Press feedback while held; the zoom starts ~1 frame after release | |

## 3. Behaviour summary

- **Taps act on touch-up; feedback comes on touch-down.** Cards shrink ~0.5 % and bar buttons brighten.
  Arc adds no delay of its own beyond ~1 frame to either.
- **Every transition can be retargeted mid-flight.** The next input reverses or redirects from the current
  position on the next frame, with no visible momentum carry-over. The exception is a tap that lands on
  a card while the switcher is still opening: it doesn't pick that card, it cancels back to the
  current tab.
- **Tabs button**: the thumbnail shows the *previous* tab. Opening the switcher pulls that card out of the
  button into the focused n−1 slot, while the current page shrinks to the right edge. One tap on the
  tabs button followed by one tap on the centred card is a quick switch to the previous tab.
- **Long-press**: + becomes voice search at ≤ 0.3 s. The tabs button has no long-press action, and a
  long hold cancels the tap.
- **Bar** hides completely when you scroll down and comes back when you scroll up. The animation wasn't
  measured.
- **Page menu (^)** and **search (+)** are bottom sheets with the same 369 × 47.5 capsule header row and
  16 pt insets. The menu dims the page and closes when you tap outside.
- **Closing a tab archives it**, and inactive tabs auto-archive after 1 day by default (12 h / 1 d / 3 d / 7 d / 30 d).

## 4. Not measured, and why

| Item | Why |
|---|---|
| Bar swipe left/right between tabs (whether it follows the finger, threshold, velocity), swipe up from the bar into the switcher, flicking a card up to close it, search typing and dismiss timing, page-menu open/close timing, the bar's hide/show animation while scrolling, edge-swipe back with no history | Session 3 (`runs/vid/s3.json`, already scripted) started at ~19:00, and every input failed with `devicectl device info details: The operation failed`. After that, `devicectl` lock-state and display queries time out and `axe doctor` reports "could not read the lock state". The last streamed frames (6:59 PM) show the iPad unlocked and in the switcher. The iPad needs someone to look at it (unlock or reconnect). Then rerun `s3.json` and the remaining flows. |
| How the search panel rides the keyboard | The iPad keyboard is a different, full-width keyboard; this needs a real iPhone |
| Bar position with the home-indicator inset; layout under the status bar | iPadOS windows have neither |
| Light-mode switcher and settings | The system was in dark mode; I didn't change system settings |
| Incognito | No entry point found (1.6) |

## 5. Files

- `shots/0x-…png`: window crops at 1× (401 × 878 = pt), measurable directly in points.
- `shots/z-…png`: 2–6× zooms with a pt grid (red every 50, green every 10), labelled in window pt.
- `shots/v-…jpg`: contact sheets, labelled in ms from the command start.
- Raw: `runs/arc-ref/full_*.png` (full 1640 × 2360 screenshots; the window is at px x 420–1222,
  y 202–1958), `runs/arc-ref/vid/s1*.h264` and `s2*.h264` with `.ts` (arrival times) and `.act` (input
  log), `s1.json` and `s2.json` (input scripts).
