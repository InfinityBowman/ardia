# Arc Search (iPhone UI): measured reference

Captured 2026-11-21 from **Arc Search 1.49.0 (88824.2)** on an iPad Air 11" (M4), iPadOS 27.2.1, in a
resizable window set to **401 × 878 pt** (target was 402 × 874 pt, the iPhone 17 Pro; the window snaps
in ~2 pt steps). The system was in dark mode. Raw media (full-res PNGs, 60 fps H.264 streams with
per-frame host timestamps, input logs) is in `apps/ios/harness/runs/arc-ref/` (git-ignored). The
downscaled stills here are in `shots/`.

> **Caveats, read first**
> - **§6 has a real iPhone recording (2026-11-22); where it differs, §6 wins.** Before it, no iPhone recording of Arc was available.
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
> - The first session (s1–s2) ended when CoreDevice stopped answering. The gestures it missed were
>   captured in a second session at ~20:45–21:00 the same day (s3–s6, §2.4–2.8), after a CoreDevice
>   restart. Between sessions Arc relaunched, and the window came back at 401 × 881 pt, then
>   401 × 878 pt at a 1–2 pt different y. Every clip was cropped to the window bounds measured at that
>   moment (§5).
> - Gestures that start in the window's bottom 30 pt, or near its bottom-left corner, are taken by
>   iPadOS as a window resize and never reach Arc (this happened twice, `full_58.png` and
>   `full_66.png`; the window was restored after each). On an iPhone that band belongs to the
>   home-indicator gesture instead, so neither tells you what Arc does there.

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
sideways. Picking a card in the switcher moves that tab to the newest position. Swiping the bar to
another tab does not (§2.4).

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

**While typing** (`17-search-typing-pen.png`): the placeholder becomes the typed text with a clear (×)
button at x ≈ 357 in place of the mic and eyes icons. Suggestion rows ("pen", "penn station", …) list
under the field, each with a magnifier and a "Browse for Me" pill; the typed prefix is bright, the
completion dimmer. The first keystroke shows the rows with a fade of ≈ 200 ms (10 frames); each later
keystroke updates the field and the rows in **one frame** (s4 type_p/e/n). On the iPad keyboard the
Return key turns blue (→) as soon as there is text.

**Reopening** the panel restores the last typed text, fully selected (`full_63.png`).

### 1.4 Page menu (^ button) (`10-page-menu.png`, `z-menu-grid.png`)

| Item | Measured |
|---|---|
| Sheet | Full width, top y ≈ 479.5, top radius ≈ 30, reaches the window bottom; a **light** material over a light page (`#ececed`), and the page behind dims (white → `#cccccc`) |
| Insets | 16 pt sides |
| Address row | Capsule 369 × 47.5 (y 495–542.5): back `<` (x ≈ 42) and forward `>` (x ≈ 81) on the left, domain `en.wikipedia.org` centred (~17 pt, semibold), link (x ≈ 321) and reload (x ≈ 359) on the right; fill `#d6d7d9` |
| Action tiles | 4 tiles, **80 × 80 pt**, radius ≈ 20, x 16 / 113 / 209 / 305 (gap ≈ 16.5), y 559.5–639.5; labels below (Find on Page, Summarize, Pin, Share), ≈ 14 pt grey, baseline ≈ 660; fill `#d2d3d4` |
| List rows | Display Options (›) y 678–725.5; Site Settings y 742–789.5; "Arc scrubbed 1 tracker / Problems? Tap to restore original page" y 805–860; each 369 wide, ≈ 47.5 tall (the tracker row is 2 lines), radius ≈ 16, gap ≈ 17 |
| Dismiss | Tapping the dimmed page, or swiping the sheet down, closes it (timed in §2.6) |

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
  deleting it. With items (`20-archive-with-closed-tabs.png`): an **Edit** button top left, a search
  field, then rows grouped by day ("Today"), each with a favicon, a title and a grey URL line, most
  recently closed first.
- **Gear** (`19-gear-settings.png`) opens this same Settings sheet.
- **Monitor button** (switcher bar, left; `18-monitor-button-sync-sheet.png`): a full-height sheet
  (top y ≈ 58, 16 pt above the window's ••• control) with a pale blue-white gradient (`#cad2e9` at the
  top → `#eaf1fd`), a pink glow at the top right, the Arc logo, "Sync with Arc Desktop" in bold violet,
  the subtitle "Search, browse, and pin to your Arc Spaces on the go.", and two full-width
  (x 36–365, 329 pt) violet buttons (`#3139f6`), **Sign in with Arc** and **I don't have an account**.
  A swipe down dismisses it. I tapped neither button.

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

### 2.4 Swiping the bottom bar between tabs (`s3`, `s3b`, `s6`; frames `v-bar-drag-200-follow-commit.jpg`, `v-bar-fast-100-commit.jpg`, `v-bar-left-at-newest-rubberband.jpg`)

**Direction.** A finger moving **right** goes to the **older** neighbour in the deck: the page slides
right and the older tab enters from the left. A finger moving left goes to the newer one. A bar swipe
does **not** reorder the deck. The switcher afterwards still shows the newest tab on the right and
puts the current (older) tab in the focus slot (`21-switcher-current-not-newest.png`).

Each row is one gesture, all horizontal along the bar at window y ≈ 849:

| Finger travel | Speed | Page followed the finger? | Result |
|---|---|---|---|
| 60, 100, 150 pt | 60–150 pt/s (1.0 s drags) | **No: not one pixel moved** | nothing |
| 100 pt | ≈ 250 pt/s (0.4 s) | yes, from the first moved frame (48 pt page offset at release) | **switched** |
| 150 pt | ≈ 250 pt/s (0.6 s) | yes | **switched** |
| 180 pt | ≈ 180 pt/s (1.0 s) | yes | **switched** |
| 200 pt | ≈ 167 pt/s (1.2 s) | yes, ≈ 0.9 : 1 (182 pt page for 200 pt finger) | **switched** |
| 40 pt, 80 pt | 670–1300 pt/s (60 ms flicks) | no | nothing |
| 120 pt | ≈ 2000 pt/s (60 ms flick) | — (too fast to see) | **switched** |
| 200 pt | ≈ 1300 pt/s (0.15 s) | yes | **switched** (both directions) |
| 200 pt left on the **newest** tab | ≈ 1300 pt/s | yes, with resistance: page reached 96 pt (≈ 0.5 : 1), an empty violet edge showed | **rubber-band**, sprang back |

What this says:
- **Start gate.** Below roughly **150–170 pt/s** the bar's pan never begins, so a slow drag does
  nothing at all. A flick of 80 pt or less never begins either. Above the gate, the page tracks the
  finger from the first frame.
- **Commit.** Every drag that began tracking committed on release, from 48 pt of page offset up, so
  the release threshold can't be bracketed from below. If there is one, it is ≤ ~50 pt at ≥ 250 pt/s.
  I saw no tracked drag snap back except the rubber-band at the deck's end.
- **Settle after release** (s3; page-edge tracking):

| Case | 50 % | 90 % | 99 % | Settle | Curve |
|---|---|---|---|---|---|
| Commit after the slow 200 pt left drag (from 207 pt to 1 pt) | 68 ms | 171 ms | 222 ms | 253 ms | spring ζ ≈ 0.89, response ≈ 287 ms, no visible overshoot |
| Commit after the fast 200 pt right swipe (new page edge 81 → 400) | 65 ms | 151 ms | 217 ms | 233 ms | ζ ≈ 0.95, response ≈ 261 ms |
| Commit after the fast 200 pt left swipe (169 → 1 pt) | 38 ms | 122 ms | 171 ms | 188 ms | ζ ≈ 1.0, response ≈ 180 ms |
| Rubber-band return at the newest tab (−96 → 0) | ≈ 56 ms | ≈ 125 ms | ≈ 200 ms | ≈ 233 ms | critically damped |

Times run from the last frame before release. The release carries the finger's velocity (initial
page speed 1250–3150 pt/s right after release). The bar icons don't move during the swipe; only the
page does, and the tabs thumbnail updates when the swipe commits.

### 2.5 Swiping up from the bar (`s4` up_slow_100_b, frames `v-swipe-up-bar-to-search.jpg`; `s5` up_from_thumb)

- **From the bar background between the tabs button and + (window x ≈ 100), 100 pt up at
  ≈ 100 pt/s:** the bar **follows the finger**. The band and the + capsule rise with it, and the
  thumbnail and ^ fade out. On release the capsule morphs into the **search field** and the
  search panel opens with the keyboard. **It opens search, not the switcher.**
- **From the tabs thumbnail (x ≈ 62), 100 pt up in 0.6 s:** nothing happened.
- No swipe-up gesture opened the switcher. The tabs button is the only route there I found.

### 2.6 Search panel and page menu (`s4`)

The page menu was tracked by template-matching its address row. The search panel was tracked by its
field where possible; whole-window frame difference was used where noted.

| Transition | Command → first frame (rig) | 50 % | 90 % | 99 % | Settle | Notes |
|---|---|---|---|---|---|---|
| **Page menu open** (tap ^): address row rises from the bar (y ≈ 832) to y 500 | 162–163 ms | 45–51 ms | **130–134 ms** | 233–248 ms | **≈ 315 ms** | Critically damped, ζ = 1.00, **response ≈ 220 ms**, no overshoot. The + capsule visibly morphs into the address row and the sheet grows out of the bar (`v-menu-open.jpg`). |
| Page menu close, tap outside | 159 ms | — | **≈ 60 ms** (sheet collapses in ~4 frames) | | 318 ms for the whole window (dim fade) | much faster than the open |
| Page menu close, swipe down (200 pt in 0.1 s) | 156 ms | | | | ≈ 235 ms | the sheet follows the finger ≈ 1 : 1 (30 pt/frame), then drops into the bar |
| **Search open** (tap +) | 170–180 ms | 148–172 ms* | 279–305 ms* | | 413–455 ms* | *Whole-window frame difference, including the iPad keyboard sliding in. The field lands on a critically damped spring, response ≈ 175–190 ms. |
| Search dismiss, tap outside | 171 ms | | field gone in **≈ 2 frames** | | 358 ms for the whole window (keyboard drop) | |
| Search dismiss, fast swipe down (150 pt in 0.1 s) | 161 ms | | | | 437 ms whole window | the field follows the finger ≈ 0.8–1 : 1 (≈ 20 pt/frame), then dismisses |
| Search dismiss, slow pull down (200 pt in 0.8 s) | 243 ms | | | | ≈ 1.35 s including the drag | dismisses on release |
| Keystroke → field and rows updated | — | | | | 1 frame | the first keystroke fades the rows in over ≈ 200 ms |
| Monitor sheet open | 219 ms | 203 ms* | 387 ms* | | 540 ms* | *whole-window difference |
| Monitor sheet swipe-down dismiss | 150 ms | 218 ms* | 301 ms* | | 403 ms* | |
| Settings open (gear) / Done | 247 / 113 ms | 102 / 160 ms* | 389 / 261 ms* | | 574 / 445 ms* | |
| Archive open / close | 145 / 179 ms | 185 / 185 ms* | 470 / 335 ms* | | 586 / 554 ms* | |

### 2.7 Closing a card in the switcher (`s5`; frames `v-card-flick-close.jpg`)

A vertical drag on the focused (n−1) card:

| Gesture | Result | Measured |
|---|---|---|
| 100 pt up at 100 pt/s, released | **snaps back** | Follows the finger ≈ 1 : 1 (90 pt for 100), **straight up**, with no change to the card's width (x stays 84–307), no rotation and no fade. Return: 90 % ≈ 125 ms, 99 % ≈ 200 ms, settle ≈ 230 ms, critically damped, no overshoot. |
| 130 pt up at 130 pt/s | **closes** | |
| 170 pt up at 170 pt/s; 250 pt up at 210 pt/s | **closes** | |
| 200 pt up in 80 ms (flick) | **closes** | Card moves ≈ 30 pt/frame during the flick and keeps going. Its bottom clears the top of the window ≈ 165 ms after release. |

- **Distance threshold: between 100 and 130 pt** of upward travel (0.16–0.21 × card height),
  even at slow speed.
- **Gap close:** the n−2 card slides right into the n−1 slot. It moves about 70 pt (−78 → 0) and
  starts ≈ 30 ms after release, while the thrown card is still leaving. Critically damped,
  **response ≈ 205 ms**: 50 % ≈ 60 ms, 90 % ≈ 150 ms, settle ≈ 215 ms after it starts. No overshoot.
  The cards further left shift with it.
- The closed tab goes straight to the Archive (§1.5).

### 2.8 Scrolling and the bar (`s5` scroll ladder on the Coffee article; strips `v-scroll-bar-hide-show.jpg`)

Drags rest at their end point, so there's no momentum unless noted. Page offset was found by
block-matching; the bar position by the + capsule.

| Drag | Page scrolled | Bar |
|---|---|---|
| Finger up 10 pt | 0 pt (within touch slop) | stays |
| Finger up 25 pt | 15 pt | **slides down with the scroll during the drag**, partly hidden; on release it springs back to fully shown in ≈ 100–150 ms |
| Finger up 50 pt | 40 pt | slides down ≈ 1.1 pt per pt of scroll and is fully hidden after ≈ 45 pt of scroll; **stays hidden** |
| Finger down 10 pt (bar hidden) | 0 pt | stays hidden |
| Finger down 25 pt | −15 pt | rises partly during the drag, then completes to fully shown ≈ 200 ms after release |
| Finger down 50 pt | −40 pt | fully shown by the end of the drag, following the scroll |
| Flick up (momentum ≈ 2.5 s) | ~1 screen | hides within the first ~3 frames and stays hidden after the momentum ends |
| Flick down | | back within ≈ 2 frames of the page starting to move |

So the bar is **scroll-linked, not a timed show/hide**. It translates with the content about 1 : 1,
clamped between shown and hidden, and on release from a partial position it springs to the nearer
end. Touch slop before the page scrolls is ≈ 10 pt.

### 2.9 Edge swipe back on a tab with no history (`s6`; frames `v-edge-swipe-no-history.jpg`)

On Coffee, which was opened by typing its URL, so it has no back history: a drag from the window's
left edge (x ≈ 2) 240 pt right in 0.5 s. **There was no back navigation, no tab switch and no Arc UI.**
The web view took it as a horizontal pan of the wide desktop page: the content shifted ≈ 73–84 pt and
the wallpaper showed at the window's right edge, then it snapped back ≈ 640 ms later. Arc has no
edge-swipe gesture of its own here. Whether it has one on a tab with history wasn't tested.

### 2.10 Release points with variable-speed drags (third session, 21:40–22:05; streams `m1`, `m2`, `m3`, `m4`)

#### Variable-speed drags with AXe on a physical device

- **What doesn't work:**
  - Held-touch moves don't work on a physical iPad. Selected input (contact tokens) is
    simulator-only: AXe 2.0.4 refuses it with "Use ordinary input and default batch settings on a
    physical device" or "Physical input uses coordinates without --agent or simulator display
    selection".
  - A legacy batch accepts only `touch --down` at A followed by `touch --up` at B. A second `--down`
    (a move), or a `swipe` or `drag` while the contact is held, fails with "Device touch steps must use
    matching down, move, and up contacts".
- **What works:** `axe draw x,y x,y … --duration T` sends one finger along a polyline, and **time is
  shared along the path by distance, at constant speed** (verified: a stroke with a mid-path cluster
  of points showed no pause).
  - **Holding still:** repeated points are refused, so append N points that alternate 0.5 pt
    *across* the drag axis. Each costs 0.5 pt of path, so the finger stays put for about
    0.5·N / speed.
  - **Reversing:** add a leg in the opposite direction.
  - The builder is `runs/arc-ref/tools/prof.py`, the trial driver (with screenshot-diff commit
    detection) is `matrix.py`, and the trial JSON is `runs/arc-ref/vid/m1.json` and `m2.json`. Those
    files are git-ignored and live only on this Mac.
- **Precision measured on the device** (`t1`, `t3`, and the trials below):
  - **Move events:** about every 17–25 ms (40–60 Hz), in steps of 5–12 pt depending on speed.
  - **Speed:** about **0.80–0.85×** what `--duration` asks for (300 → 240 pt/s; 600 → ~510 pt/s).
  - **Fit to a straight line:** 2.5 pt rms (5.5 pt max) residual, i.e. **±1 event (~±20 ms)**.
    Occasional gaps of 50–70 ms with no move (one in ~15 strokes).
  - **Holds overrun:** a "0.3 s" hold of 360 points lasted **0.47–0.70 s**, about 1 ms of overhead
    per point.
  - **Start latency:** the first move lands 190–270 ms after the command starts.
  - **Release:** lifting from a hold gives zero release velocity (no fling on a web view). Lifting
    mid-leg carries that leg's velocity, and a reversal leg of ≥ 30 pt flips it.
  - **Verdict: precise enough for release-point work.** Distances are good to about one event,
    roughly ±10 pt. Speeds should be quoted as measured, not as requested.
- **Pitfall:** check that the bar is showing before a bar trial. My first `m1` run went to a page
  whose bar had scrolled away (`m1_invalid_bar_hidden.h264`) and was discarded.

#### Bar swipe release matrix (`m1`; Lighthouse, the newest of 4 tabs, finger moving right toward the older tab; start window x 100, y 849; requested 600 pt/s, observed ≈ 510 pt/s)

Page offset is the page's left edge, found as the strongest vertical edge in each frame.

| Profile | Finger travel | Page offset at release | Result | After release |
|---|---|---|---|---|
| fast, **stop dead, hold ≈ 0.5 s**, lift | 30 pt | 0 (pan never began) | nothing | — |
| | 60 pt | 47 pt | **snap back** | 50 % 103 ms, 90 % 154 ms, ≤ 3 pt at 170 ms; spring ζ ≈ 0.84, response ≈ 295 ms |
| | 90 pt | 77 pt | **snap back** | 50 % ≈ 45 ms, 90 % ≈ 130 ms, ≤ 3 pt at ≈ 150 ms |
| | 120 pt | **107 pt** (27 % of width) | **snap back** | 50 % ≈ 54 ms, 90 % ≈ 129 ms, ≤ 3 pt at ≈ 167 ms; ζ ≈ 0.92, response ≈ 230 ms |
| fast, **lift while moving** | 30 pt | 0 | nothing | — |
| | 60 pt | 33 pt | **snap back** | 50 % 81 ms, 90 % 149 ms, rest at ≈ 150 ms; ζ ≈ 0.88, response ≈ 280 ms |
| | 90 pt | 60 pt | **commit** | |
| | 120 pt | 78 pt | **commit** | (`v-held-bar-lift90-commit.jpg`) |
| fast, **reverse**, lift | +60 / −30 | 27 → back | **snap back** | rest ≈ 140 ms after the turn |
| | +90 / −45 | 58 → back | **snap back** | rest ≈ 200 ms after the turn |
| | +120 / −60 | 76 → back | **snap back** | rest ≈ 235 ms after the turn |
| | +120 / −100 | 88 → back | **snap back** | rest ≈ 285 ms after the turn |

Together with §2.4 (slow 180 pt at ≈ 180 pt/s committed, with ≈ 160 pt page offset still moving):

- **The release decision is driven by velocity, not position.** A page stopped at 107 pt snaps back,
  while a page still moving at ≈ 500 pt/s commits from 60 pt. Any reversal before lift snaps back,
  even from 88 pt.
- At ≈ 500 pt/s the commit point lies between **33 and 60 pt** of page offset (60–90 pt of finger
  travel).
- *Inference, not measured:* this fits a projected-position rule, offset + v·k ≥ about half the
  width, with k ≈ 0.25–0.33 s.
- **Following:** the page follows the finger with an **eased lag**, not rigidly. With the finger at
  constant speed, the offset decelerates into its final value over ~150–250 ms, and the plateau sits
  10–15 pt short of the finger (touch slop).
- **Snap-back:** critically to slightly under-damped (ζ ≈ 0.84–0.92), response ≈ 230–295 ms, no visible
  overshoot. It is at rest **150–170 ms** after release from a hold.

#### Card flick-close matrix (`m2`, `m3`, `m4`; focused n−1 card, finger moving up from window y 519)

The card follows the finger ≈ 1 : 1 (it ends 11–14 pt short of the finger: slop).

| Profile | Finger travel | Card displacement at release | Result | After release |
|---|---|---|---|---|
| fast, **stop dead, hold 0.65–0.70 s**, lift | 100 pt | 89 pt | **snap back** | 50 % 108 ms, 90 % 184 ms, ≤ 1 pt at 258 ms; ζ ≈ 0.88, response ≈ 320 ms |
| | 115 pt | 104 pt | **snap back** | 50 % 51, 90 % 132, ≤ 1 pt at 199 ms; ζ 1.0, response ≈ 200 ms |
| | 130 pt | 118 pt | **snap back** | 50 % 67, 90 % 132, ≤ 1 pt at 199 ms; ζ 1.0, response ≈ 218 ms |
| | 150 pt | ≥ 136 pt (card top reached the window top) | **snap back** | 50 % 50, 90 % 149, ≤ 1 pt at 216 ms; ζ 1.0, response ≈ 217 ms |
| fast (≈ 510 pt/s), **lift while moving** | 20 pt | ≈ 10 pt | **closes** | see "exit" below |
| | 40 pt | 30 pt | **closes** | see "exit" below (`v-held-card-lift40-close-exit.jpg`) |
| fast, **reverse**, lift | +150 / −10 | 136 → 129 | **closes** | the 10 pt reversal was too short to flip the release velocity |
| | +130 / −30 | 118 → 88 | **snap back** | rest ≈ 230 ms after release |
| | +150 / −50 | 136 → 89 | **snap back** | rest ≈ 265 ms after release |

Earlier slow continuous drags (§2.7): 100 pt at 100 pt/s snapped back, and 130, 170 and 250 pt at
130–210 pt/s closed.

- **Card close is also decided by velocity.** A card stopped dead never closes, even pulled
  ≥ 136 pt. A card still moving up at release closes from only ~10 pt at ≈ 500 pt/s, or from 130 pt
  at ≈ 130 pt/s. A downward reversal of ≥ 30 pt before lift always snaps back.
- So the "100–130 pt" from §2.7 is the slow-speed boundary only, not a distance threshold.
- **Unexplained exit.** After the two *short* fast flicks (20 and 40 pt), Arc closed the card **and
  left the switcher**:
  - the whole deck shrank into the tabs button;
  - a full-window in-app page took its place: "Want links to open in Arc? / Make Arc your default
    browser… / Set Arc as Default Browser" (`22-empty-state-after-short-flick.png`,
    `v-held-card-lift20-close-exit.jpg`);
  - reopening the switcher showed the deck intact, minus the closed card.

  A long flick (200 pt) and the +150/−10 close stayed in the switcher. I didn't find the cause. Don't
  copy it without checking it on a real iPhone. It isn't a system prompt, and its button wasn't tapped.

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
- **Bar** is scroll-linked. It slides away ~1 : 1 as the content scrolls down, is fully hidden after
  ≈ 45 pt, slides back as you scroll up, and on release from partway springs to the nearer end (§2.8).
- **Bar swipe** follows the finger but only starts above ≈ 150–170 pt/s. A slow drag does nothing.
  Once it starts it commits, and it settles on a ζ ≈ 0.9–1.0 spring in ≈ 190–250 ms. At the newest tab
  a swipe toward newer rubber-bands at ≈ 0.5 : 1 (§2.4).
- **Swipe up from the bar** follows the finger and opens **search**, not the switcher (§2.5).
- **Card close** follows the finger straight up. Whether it closes depends on the **release
  velocity**:
  - stopped dead, it never closes (even at ≥ 136 pt);
  - moving up at ≈ 500 pt/s, it closes from ≈ 10 pt;
  - moving up at ≈ 130 pt/s, it closes from 130 pt;
  - pulled back down ≥ 30 pt before release, it snaps back.

  The gap closes on a ≈ 0.2 s critically damped spring (§2.7, §2.10).
- **Bar swipe commit** is decided by release velocity as well: stopped at 107 pt it snaps back,
  moving at ≈ 500 pt/s it commits from 60 pt, and a reversal always snaps back. Snap-back is at rest
  in 150–170 ms (§2.10).
- **Page menu (^)** and **search (+)** are bottom sheets that grow out of the + capsule, with the same
  369 × 47.5 capsule header row and 16 pt insets. Both follow a downward swipe and close on a tap
  outside. Closing is much faster than opening: the menu opens in ≈ 315 ms (response 0.22 s) and
  collapses in ≈ 60 ms.
- **Monitor button** opens the "Sync with Arc Desktop" sign-in sheet; the **gear** opens Settings.
- **No edge-swipe** gesture on a tab with no history: the web view gets the pan (§2.9).
- **Closing a tab archives it**, and inactive tabs auto-archive after 1 day by default (12 h / 1 d / 3 d / 7 d / 30 d).

## 4. Not measured, and why

| Item | Why |
|---|---|
| ~~Bar-swipe release threshold~~ | Measured in §2.10 with variable-speed `draw` strokes |
| The exact projection constant behind both release rules | Speeds were tested at ≈ 130–180 and ≈ 500 pt/s only. A sweep of release speed at a fixed distance (100, 200, 300 pt/s…) would pin it down. |
| Why a short fast card flick also exits the switcher | Seen twice (§2.10). The cause wasn't isolated. |
| Swipe up from the bar's very bottom, or from the tabs button corner | iPadOS takes those as a window resize (Caveats) |
| Edge swipe on a tab **with** back history | Not tested; only the no-history case was asked |
| Exact search-panel open curve | The field morphs out of the + capsule, so template tracking only locks on for the last ~40 pt; the earlier part is the whole-window difference, which includes the iPad keyboard |
| How the search panel rides the keyboard | The iPad keyboard is a different, full-width keyboard; this needs a real iPhone |
| Bar position with the home-indicator inset; layout under the status bar | iPadOS windows have neither |
| Light-mode switcher and settings | The system was in dark mode; I didn't change system settings |
| Incognito | No entry point found (1.6) |

## 5. Files

- `shots/0x-…png`: window crops at 1× (401 × 878 = pt), measurable directly in points.
- `shots/z-…png`: 2–6× zooms with a pt grid (red every 50, green every 10), labelled in window pt.
- `shots/v-…jpg`: contact sheets, labelled in ms from the command start.
- `shots/perm-0x-…png`: the iPad's Settings › Privacy & Security › Microphone and › Speech
  Recognition after Arc Search was switched back on in both (see below).
- Raw: `runs/arc-ref/full_*.png` (full 1640 × 2360 screenshots). The window sits at px x 420–1222, at
  y 202–1958 (s1, s2, s4), y 198–1960 (s3b, 401 × 881 pt) or y 204–1960 (s5, s6). The streams are
  `runs/arc-ref/vid/s1…s6.h264`, each with `.ts` (arrival times) and `.act` (input log). `s3.h264` is
  the failed first attempt; `s3b` is the rerun.

### Session log

In the first session, a 0.3 s hold on + triggered Arc's microphone and speech-recognition prompts,
and I answered both **Don't Allow**. That was a mistake: the owner wanted to be asked. In the second
session I switched Arc Search back **on** in Settings › Privacy & Security › Microphone and
› Speech Recognition (`shots/perm-01-…`, `perm-02-…`; AXe confirmed both switches went off → on).
Nothing else in Settings was changed. The 8 test tabs were closed (they're now in Arc's Archive),
leaving the farewell tab and one tab of the owner's that was already there, and Arc's window is back to
full screen.

In the third session I opened 16 Wikipedia test tabs and closed all of them (they're in the Archive
too). The farewell and owner tabs were untouched, and Arc is back to full screen. No system prompt
appeared.

## 6. iPhone measurements (owner's recording, 2026-11-22)

The owner's screen recording of an iPhone 17 Pro (1206 × 2622 px = 402 × 874 pt at 3×, 60 fps, 11.6 s,
dark mode) shows Ardia Fork from 0 to ≈ 6.6 s and Arc Search from ≈ 7.4 s (frames 0–692; the iOS app
switcher sits between them). Frame numbers below are the recording's own (`ffmpeg -fps_mode passthrough`,
frame n at n/60 s). Where this section disagrees with §1–§2, this section wins: it is a real iPhone, with
the status bar and the home indicator.

### 6.1 Page bar (frames 590 white page, 660 #141316 page)

| Item | iPhone | iPad (§1.1) |
|---|---|---|
| Button centre line | y **829.75**, i.e. **44.25 pt above the screen bottom**, 10.25 pt above the 34 pt home-indicator inset | 28.5 pt above the window bottom |
| + capsule | y 809.7 → 849.7, x ≈ 162.3 → 239.1 (≈ 76 × 40 incl. a 1 px rim) | 75.5 × 39.5 |
| ^ circle | y 812.7 → 846.7, centre x 360.7 (≈ 34 pt incl. rim) | 33.5 pt |
| Band | top at y **797**, **77 pt** tall, to the screen bottom; the band top is 32.75 pt above the line | 52.5 pt, 24 pt above the line |
| Top edge | a 1 px hairline: `#343336` over `#222124` (white ≈ 0.08) | no hairline |
| Fade above the band | none (≤ 3 levels of shadow within 3 pt) | ≈ 25 pt fade |
| Home indicator | y 861 → 865.7 | — |

Band colour, sampled at x = 120 and 300 (grey average):

| Page under the band | Band top (y 798–800) | Band bottom (y 870) | + capsule | Glyphs |
|---|---|---|---|---|
| White | `#6a6667` (104) | `#827375` (123) | ≈ +19 over the band (white ≈ 0.1) | white |
| `#141316` | `#222124` (34) | `#201f22` (32) | `#383739` (+22) | white |

- The band is a dark translucent material over the blurred page, in dark mode, whatever the page's
  colour: on a white page it is mid grey with white glyphs, and the page's text shows through it
  blurred. The page colour is not sampled, so nothing tints it.
- Fitting both pages: a grey ≈ `#282828` at α ≈ 0.69 at the top and ≈ 0.58 at the bottom over the page.
  Ardia reaches the same levels with a `.light` blur (its backdrop maps page level p to ≈ 0.74 p + 35 on
  iOS 27.2) under `#171717` at 0.60 → `#0D0D0D` at 0.48: 104 → 123 on white, 33 → 32 on `#141316`.
- Light mode was not recorded.

### 6.2 Switcher cards (frames 496 at rest, 615–624, 660 for the page)

| Item | iPhone | iPad (§1.2) |
|---|---|---|
| Card content | the page **below the status bar** (page y 62 → 874), drawn at **0.6995** scale (template match of the page in frame 660 against the n−1 card in frame 496, mean error 3.3 levels) | the whole window |
| Card size | **281.2 × 568 pt** (the width ratio is unchanged, 0.70 of the screen) | 281 × 607 |
| n−1 card | left 84.3, top **167.3**, bottom **734.7** | left 84, top 135, bottom 742 |
| n (current) card | left 309.5, top 166.8, bottom 735.1 (spacing 225 pt) | left 308–309, 224 pt |
| Vertical rule | the favicon row (card top − 28 = 139.3) is 77.3 pt below the status bar (62) and the card bottom is 75.3 pt above the + capsule's top (810): the header-plus-card block is centred between the two | centred on the window |
| Press feedback | the pressed card's top moves 167.3 → 168.7 and its bottom 734.7 → 733.4 (frame 624, the frame before the zoom) | ≈ 0.5 % |
| Switcher bar | the same line as the page bar: + capsule y 809.7 → 849.7 (centre 829.75), monitor circle centre (40.7, 829.7), fills `#353040`/`#343443` on `#1f1a28` | 850 |

### 6.3 Opening a card that isn't the newest (frames 624–651; Ardia's old behaviour at frames 33–55)

- Frame 624 is the touch-down (press feedback), 625 the first frame of the zoom. The tapped card (Mocks,
  the n−1 card) **stays on top of every other card** and zooms in place.
- The deck spreads apart around it: the newer card (the white current tab at x 309) slides **right**, off
  the screen by frame 628 (≈ 50 ms), and the older cards slide **left** off the screen. No card flies into
  the tabs button and nothing crosses the tapped card.
- The switcher bar keeps its icons for ≈ 3 frames, then the page bar's icons cross-fade in. The tabs
  button's two thumbnails (the old newest tab in front, the one before it behind) **rise from below the
  screen**: first visible at frame 630, at rest at frame 642. Their centre falls 14.2, 9.5, 6.0, 3.6, 2.0,
  1.1, 0.5 pt short of rest on frames 634–640: a critically damped spring, **response ≈ 0.19 s**, starting
  **≈ 71 pt below rest** at ≈ 58 ms after the zoom's first frame (fit rms 0.4 pt). x and tilt don't change.
- Tapping the newest card instead (frames 497–507): the zoomed card is on top while it is large, and the
  n−1 card (and n−2) shrink into the tabs button's front (and back) thumbnail, drawn over the page once
  they are small, at rest by ≈ frame 507 (≈ 170 ms).
- Ardia before this round: every other card flew to the tabs button above the tapped card, so the newest
  card crossed in front of it (frames 34–40).

### 6.4 The tabs button's thumbnails (frames 471–507, 625–642, 660)

- **At rest** (frame 660, corners read off a 12× zoom): the front thumbnail is **24.5 × 27 pt**, tilted
  **+9°**, centred at (54.3, line − 5.1); the back one is ≈ 24.5 × 27.5 pt, tilted **−18°**, centred at
  (40, line + 3); corner radius ≈ 3.5–4. They show the top of each page below the status bar. (iPad §1.1:
  28 × 29 at +8°.)
- **Opening the switcher** (471–476): the thumbnails leave the button at once and *are* the n−1 and n−2
  cards: they grow and untilt into their deck slots while the page shrinks into its own; the monitor
  circle replaces them in the same frame. The page underneath does not show through.
- **Opening the newest card** (497–507): the n−1 (and n−2) cards shrink and re-tilt into the front (and
  back) thumbnail, over the bar, at rest ≈ 7–9 frames after the zoom starts (≈ 150 ms; the page's own
  zoom takes ≈ 300 ms).
- **Opening an older card** (625–642): the thumbnails rise from below the screen, §6.3.

### 6.5 Search panel growing out of the + capsule (owner's second recording, 2026-11-22; iPad check the same day)

A second recording (iPhone 17 Pro, 1206 × 2622 px = 402 × 874 pt, variable frame rate ≈ 60 fps, 12.1 s,
dark mode) has Ardia from 0 to ≈ 6.5 s and Arc Search from ≈ 6.7 s: a swipe-up open at 7.84–9.3 s,
a tap-outside close at 9.84–10.15 s, a tap-+ open at 10.64–11.08 s and a tap-outside close at 11.48–11.8 s.
Frames below are this recording's (1-based, `-fps_mode passthrough`), times from each move's first moving
frame. Positions were tracked on the + capsule / field in column x = 226 (`runs/search3`). **The owner's
keyboard is Wispr Flow, a third-party keyboard**, so the keyboard's own timing below is Wispr's, not the
system keyboard's. This section replaces the old iPad-only notes.

**Tap + to open (frames 637–663)** runs every part at once; it is not sequential.

| Part | Measured |
|---|---|
| Panel (field top) | 812 → 235.5 (travel 576.5); spring fit response **≈ 0.30 s**, ζ 0.94–1.0, starts ≈ 1 frame after the touch frame (rms 4.6 pt). 50 % at ≈ 100 ms, 90 % at ≈ 200 ms, settled ≈ 400 ms |
| Capsule width | 74 → 370; response **≈ 0.25 s**, ζ ≈ 0.95, starts ≈ 25 ms before the rise: 102 at 17 ms, 228 at 67 ms, 290 at 100 ms, 330 at 117 ms, 368 at 250 ms. Height 35–40 → 47.5 over the same time |
| + glyph | stays at the capsule's leading side (centre 37.75 → 15 pt inside the left edge as it widens), fully visible to ≈ 67 ms, gone by ≈ 117 ms |
| Field content | laid out at the final width and anchored to the capsule's **left** edge, clipped by the capsule: the caret and "Search…" show from the first moving frame (focus is immediate), the text starts 21.5 pt right of the + glyph and slides to 23–24.5 pt inside as the + fades; the mic appears at ≈ 117 ms and the eyes at ≈ 150 ms as the right edge uncovers them |
| Tabs button and ^ | ride up with the panel's top row (^ centre 828.5 → 806 → 778.5 on the first two frames) and fade: ≈ 0.85 at 33 ms, 0.5 at 67, 0.3 at 83, 0.15 at 117–133, gone ≈ 200 ms; the widening capsule draws over the tabs button |
| Keyboard (Wispr) | first visible ≈ 100 ms (top ≈ 751), rises ≈ 330 ms, lands ≈ 433 ms at top ≈ 522. The panel leads it: field top minus keyboard top is −239 at 100 ms, −288 at 200 ms, −299 at rest, so the panel is its own spring to the keyboard's final frame, not riding it 1 : 1 |
| Page | recedes into a card behind the panel: scale **0.952** about the status bar's bottom (y ≈ 62.6), left edge 10 pt, top 62.3, corner radius ≈ 24, darkened ≈ 22 % (text 250 → 195), over a ≈ `#17161F` backdrop; the card's left edge moves 20 → 29 pt over ≈ 200 ms |

**Close by tapping the page (frames 687–708 and 589–609, same both times):** the field drops 235 → 808
and narrows 370 → 78 (height 48 → 38) on one critically damped spring, **response ≈ 0.30 s** (fits 0.295–0.307,
rms ≤ 1.5 pt), starting ≈ 45 ms after the last still frame; the + glyph returns at the leading side by
≈ 67 ms and "Search…" slides back out to its right; the tabs button and ^ ride down on the panel's top
row (^ centre ≈ field top + 17) and fade in from ≈ 100 ms (0.15) to ≈ 250 ms (1). The page card grows back
on a spring, t0 ≈ 45 ms, response ≈ 0.23–0.27 s. Wispr's keyboard vanishes in one frame.

**Swipe up from the bar (frames 469–555):** the panel follows the finger with the + capsule riding its top
edge at its bar size (76 × 37), 812 → 549 over 0.75 s (≈ 350 pt/s); the tabs button and ^ fade within
≈ 4 frames of the drag starting; suggestions slide up underneath. After the finger stops and lifts
(frame 519) the capsule widens in place (78 → 322 in ≈ 150 ms, y within 10 pt), then the keyboard appears
(frame 529, ≈ 165 ms after the lift, almost full height in one frame) and the panel rides up with it,
539 → 235 over ≈ 350 ms. This is the sequential open; a tap is not.

**Panel at rest (frame 660, dark mode, over a near-black page):**

| Item | Measured |
|---|---|
| Panel | top 218.67 with a 1 px hairline (`#5A595E`, white ≈ 0.24), fill ≈ `#212023` (33,32,35), ≈ 38 just around the field; 30 pt top radius; visible height above Wispr's keyboard ≈ 304 pt with four rows |
| Field | x 16 → 386 (370), y 236 → 283.67 (47.5), 17.3 pt below the panel top; fill `#3A393C`, a 1 px stroke all round (≈ 92, white ≈ 0.17); "Search…" `#9F9FA6` starting x ≈ 40 (24 pt inside); mic centre 312, eyes centre 356, both ≈ `#979699` |
| Rows | 56 pt pitch, first row centre 34.5 pt below the field (6.5 pt gap); favicon 22 × 22 at x 18–40 (centre 29), or a globe glyph 18.7 × 19 at x 19.7–38.3 in ≈ `#D0CFD1`; title 17 pt pure white `#FFFFFF` from x ≈ 49; one line each |
| Icons by kind | tabs and history with a favicon show it; entries without one (Desk, Mocks) show the globe; the iPad's search suggestions show a magnifier (§1.3) |

**Is the panel solid?** No. On the iPad (Arc Search 1.49, iPadOS 27.2.1, 2026-11-22 ≈ 14:50), opened over a
white Wikipedia page:
- dark mode: the panel is a translucent dark material, ≈ `#717273` (112–123) over the white page, field
  ≈ `#777778`, white text; over a dark page it reads ≈ `#242424` like the iPhone's;
- light mode (switched with `axe settings set --appearance light`, then back to dark): a near-white material,
  `#F4F4F5` at the top to `#E9E9EA` lower down, field `#D1D2D2`, placeholder ≈ `#737374`, row titles ≈ `#171717`.

**Ardia now** (`App/Search/KeyboardRider.swift`, `SearchTray.swift`, `SuggestionRowView.swift`):
- Tap +: the panel rises on its own critically damped spring (response 0.30 s) from the bar to where the
  keyboard will end (the last keyboard height, kept in `searchPanel.keyboardLift`; 336 pt before the first
  keyboard), retargets on the keyboard's will-change notification and follows later keyboard changes on
  the keyboard's own curve. A UIKit capsule (field fill, 1 px edge, + glyph, "Search…" or the reopened text,
  caret, mic and eyes at the field's final offsets from its left edge) widens from the + capsule into the
  field on a 0.25 s spring, clipped to its own shape; the + fades after 40 ms over 80 ms and the text slides
  from 21.5 pt right of it to 23 pt inside. A cover in the panel colour hides the real field until the
  capsule hands over at 300 ms (80 ms fade), or at once on the first keystroke. The panel body fades in over
  100 ms so the bar's band doesn't snap. The field still focuses in the same pass as before.
- The tabs button and ^ are a live, non-interactive copy of the bar's (`BottomBar(iconsOnly:)`) on the
  panel's top row: they ride up with it and fade over 0.2 s on open; on close they ride down and fade in
  from 100 to 250 ms, and the panel body fades out from 360 to 440 ms onto the real bar, once the panel is
  within ≈ 2 pt of it (earlier, the copy and the real icons showed doubled).
- Close: the panel sinks into the band and the field shrinks into the + capsule on 0.30 s springs, the +
  returning after 80 ms. Every delayed fade is a keyframe animation, so it runs on the render server.
- Look: solid `#212023` in dark mode (the owner's call: Arc's look over dark pages, on every page), and
  Arc's light-mode colours (`#F0F0F1`, field `#D1D2D2`, text `#171717`) in light mode; Incognito keeps
  `#151517`. Rows: favicon (globe while missing) for tabs, history and bookmarks; globe for a typed URL;
  magnifier for searches; 22 pt icons at x 18–40, titles at x 49; the typed prefix bright and the
  completion dimmer (§1.3). Panel height above the keyboard 304 pt.
- Not built: the swipe-up drag that follows the finger (Ardia's bar still rubber-bands up to 60 pt and
  opens on release), and the page receding into a card.

### 6.6 Page menu growing out of the bar (`s4` menu_open, iPad frames; the iPhone recording has no page menu)

- Arc (§1.4, §2.6, `v-menu-open.jpg`): the sheet rises out of the bar on a critically damped spring,
  response ≈ 0.22 s, and **the + capsule** (not the ^ circle) visibly widens into the address row as it
  rises; the bar's thumbnail rises a little and fades under the sheet. Closing by tapping the page
  collapses the sheet in ≈ 4 frames; a swipe down follows the finger 1 : 1, then drops into the bar.
- Ardia: the menu is now its own panel over the page instead of a system sheet. Full width, 30 pt top
  corners, the bar band's material, the page dimmed by black at 0.2. At rest the address row is
  centred on the bar line under the + capsule; rising (offset on a critically damped spring, response
  0.22 s), it widens from 75.5 × 39.5 to 369 × 47.5 and its contents fade in while a + glyph fades out.
  Closing reverses it on a 0.12 s spring; dragging the panel follows the finger and closes past 90 pt
  or on a downward fling.
- Layout follows §1.4: address row 369 × 47.5 (back, forward, domain, pin, reload), four 80 × 80 tiles
  (radius 20, labels below: Find on Page, Reader, Copy Link, Share), then separate rows (47.5 tall,
  radius 16, 16.5 apart): Display Options (expands to Night Shade, Page Zoom, Desktop Site,
  Translate), Site Settings, Block Ads and Trackers, and More (Send, Print, History, Bookmarks,
  Downloads, Open in Default Browser). Arc's light-mode fills `#d6d7d9` (row) and `#d2d3d4` (tile);
  dark mode is a guess, white at 0.1.

- **Material, measured on the iPad 2026-11-22** (dark mode both times, `runs/search3/ipad-arc-menu-*.png`):
  Arc's menu follows the **page's** tone, not the system appearance, and so differs from its search panel
  (§6.5). Over a white page: panel `#F4F4F4` at the top to `#E8E8E8` lower down, address row `#D6D7D7`,
  tiles `#D6D5D6`, rows ≈ `#C9C9CB`, dark text and outlined dark-grey icons. Over a near-black page: panel
  `#232323` to `#2D2A2B`, address row `#4D4C4C`, tiles `#444242`, rows `#534D4E`, white text and icons;
  a 1 px light hairline on the panel top. Every row carries a leading outlined icon (Display Options a
  document with a picture, Site Settings a gear), its centre 30 pt from the row's left and the title at 52 pt.
- Ardia (since this round): the menu's colour scheme follows the bottom page tone Ardia already samples
  for the status bar (falling back to the app's appearance), with solid fills at those values (panel
  `#F0F0F0` / `#282728`, address `#D6D7D9` / `#4D4C4C`, tiles `#D2D3D4` / `#444242`, rows `#CDCDCF` /
  `#4F4D4E`) instead of the bar's blurred band, which let page colours show through as blotches. Rows
  have 17 pt titles and an SF Symbol at Arc's offsets: Display Options `doc.text.image`, Download Video
  `square.and.arrow.down`, Site Settings `gearshape`, Block Ads and Trackers `shield.lefthalf.filled`,
  More `ellipsis.circle`, and inside them Night Shade `moon`, Page Zoom `plus.magnifyingglass`, Desktop
  Site `desktopcomputer`, Translate `translate`, Send `paperplane`, Print `printer`, History `clock`,
  Bookmarks `book`, Downloads `arrow.down.circle`, Open in Default Browser `safari`.
- The address row now sits 16 pt below the panel top, as Arc's (it was 50 pt: the menu's scroll view
  counted a 34 pt top content inset, the bottom safe area, into its height, so the panel grew by 34 pt
  above its content, and its closed pose left the address row 34 pt below the bar line).

### 6.7 Turning back to the switcher while an older card lands (iPad `s2` r3/r5, `v-tabs-during-zoom.jpg`)

- Arc: tap an older card (Penguin, the n−1 card), then the tabs button 154 ms into the zoom (r3) or
  302 ms after it (r5). The page shrinks straight back into the **rightmost** (current) slot, and the old
  newest card (Linear) flies out of the tabs button into the n−1 slot, as in a normal open from the
  page (frames 293–460). A picked card is the newest from the moment it's picked.
- Ardia before the fix: the model already made the tab the newest at the tap, but the turn-back reused
  the switcher's old order, so the tapped card shrank back into its old slot with the old newest to its
  right (owner's iPhone screenshot, 2026-11-22). After the landing, a fresh open was already right.
- Ardia now: the turn-back takes the model's order, puts every other card in its open-from-page start
  pose (the n−1 and n−2 as the tabs button's thumbnails, the rest off screen) and runs the normal open,
  so the zooming card shrinks into the rightmost slot from wherever it is. Bar swipes still don't
  reorder (they freeze the order, as before).
- harness: `deck-turnback` drives this from an in-app script (AXe taps are about a second apart on
  this Mac, too slow to land mid-landing) with the tabs button 50, 150 and 300 ms into the landing and
  500 ms after it, and fails if any switcher shows the selected tab anywhere but rightmost
  (`deck.misordered`). Before the fix: 6 of 8 misordered; after: 0.

### 6.8 Start page, Archive and Incognito (§1.5, §1.6; `14-`, `20-`, `22-`; composite `runs/restyle2/B3-start-archive-incognito-compare.png`)

- **No tabs** (Arc `22-`): the app mark centred at about half height, "Want links to open in Arc?"
  (17 pt semibold), a grey two-line subtitle and a 34 pt "Set Arc as Default Browser" button (radius ≈ 10,
  white ≈ 0.14), over the dark backdrop, with the page bar's three controls. Ardia shows the same block
  (app icon 128 pt, "Want links to open in Ardia?", the button opens Settings) on the start page when
  there are no synced spaces, and in the empty switcher. Once Ardia is the default browser it offers Sync
  with your Mac instead, and with nothing left to offer, just "No open tabs". The switcher keeps an
  "Open Archive" link under it (Arc has none). The start page's bar is now the page bar: band, tabs
  stack, + capsule, and a gear circle where the page has ^.
- **Archive** (Arc `14-`, `20-`): a `#1c1c1d` sheet, "Archive" centred, a violet (`#7b8df7`) ✓ circle at
  the top right and **Edit** at the top left, a search capsule, day headers ("Today", grey, not
  uppercase), and inset cards (`#2c2c2e`) of favicon, title and grey address rows, ≈ 50 pt each. Empty:
  "Nothing here yet!" (bold) over a grey line. Ardia keeps its ••• menu (auto-archive interval, Delete
  All) beside the ✓, and Edit selects rows for a Delete button.
- **Incognito**: Arc Search 1.49 has none (§1.6), so Ardia's keeps the same layouts in dark: the empty
  switcher and start page show the eyes mark with "You're browsing Incognito" and a line on what isn't
  saved; the search panel keeps its Incognito label and "You're browsing Incognito" while the field is
  empty.

### 6.9 Downloads on the page bar and in the page menu (Ardia's own; Arc Search has no downloads UI)

Arc Search on iPhone shows nothing while a file downloads, so this is Ardia's design, built from the
pieces measured above. Captures: `runs/downloads-ux/` (git-ignored).

- **Ring on ^**: a 2.5 pt ring sits 1 pt outside the 33.5 pt circle (radius 19.5 to the stroke's centre),
  starting at 12 o'clock and filling clockwise. The track is the bar glyph colour at 18 %; the arc is the
  bar glyph colour, so it follows the page tone like the chevron. It shows the combined progress of
  every running download: bytes over bytes when all sizes are known, otherwise the mean fraction. When
  any download is still finding its stream (no size, no fraction), a 28 % arc spins once per 0.9 s (with
  Reduce Motion it pulses instead). It is drawn by Core Animation, read from the downloads at most every
  100 ms, and each step animates linearly over 120 ms, so SwiftUI never redraws the bar for it. With no
  download nothing runs and the layers aren't built.
- **Start**: tapping Download Video shows the spinning ring as the menu closes (1 ms after the touch
  ends in the harness), before the page scan finishes, plus the "Downloading Video" toast.
- **End**: when the last download finishes the ring fills, a 33.5 pt green circle with a white check
  fades in over the chevron in 0.18 s, holds 1.1 s and fades out. Failure and cancel fade the ring out
  without a check.
- **Touch and hold ^** (0.45 s) while the ring shows opens Downloads instead of the menu.
- **Page menu row**: the first row group under the tiles (above Display Options), so the address row still
  grows out of the + capsule. One download: a 32 pt thumbnail centred 30 pt from the edge, the title at
  52 pt like the other rows, "27 % · 1.7 MB of 6.2 MB · 20 s left" under it, and a 28 pt stop control
  (progress ring around a square). Several: "3 downloads · 35 %" over "6.5 MB of 18.7 MB" with a chevron.
  Finished files nobody has looked at yet follow it (two at most) with **Save to Photos** for videos or
  **Open** otherwise; closing the menu, opening Downloads or acting on the file counts as looking.
  Tapping a row opens Downloads.
- **Completion toast**: "Downloaded" with the file name, a **Save to Photos** (video) or **Open** button
  and Share, for 5 s, on a solid toast fill. A download that finishes in the background shows its toast
  when the app comes back (within 10 minutes).
