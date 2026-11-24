# iOS performance harness

Drives the iOS app on a simulator with real touches, films it, and measures it — no person needed.

```sh
python3 harness.py build             # Release build onto the "Ardia Harness" simulator
python3 harness.py run deck-rapid    # launch on fixture tabs, run the scenario, print the report
python3 harness.py list              # scenarios
python3 harness.py ui                # what is on screen (accessibility labels and centres)
```

`ARDIA_HARNESS_SIM` (simulator name) and `ARDIA_HARNESS_DERIVED` (derived-data path) let a second agent run on its
own simulator and build. `run <scenario> --trace` adds a Time Profiler trace and names what filled each slow main pass.
Scenarios added for the motion pass: `deck-close` (flick cards away), `deck-surfaces` (Archive, Incognito, the empty
switcher, the start page, from an in-app script), `page-swipe` (back and forward swipes on `fixtures/nav-*.html`), `page-swipe-script` (the same after a pushState link on `fixtures/spa-a.html`)
`display-options` (expand and collapse Display Options in the page menu at rest, then tapped quickly) and
`more-options` (the same for More).

Each run writes `runs/<time>-<scenario>/` with `video.mp4`, `probe.jsonl`, `meta.json` and `report.json`.

## How it works

- **Driving:** [AXe](https://github.com/cameroncooke/AXe) (`brew install cameroncooke/axe/axe`) sends HID touches
  in one `axe batch` session. Unlike XCUITest it never waits for the app to go idle, so it can tap mid-animation.
- **Content:** `-ArdiaDemo -ArdiaHarnessSeed <url>` fills an in-memory store with the pages in `fixtures/`,
  served on `127.0.0.1:8765`, so every run sees the same tabs.
- **Inside the app:** `-ArdiaProbe` turns on `App/Harness/HarnessProbe.swift`, which logs every display-link
  frame, every main run-loop pass over 4 ms, and named marks (`HarnessProbe.mark("tabs.tap")`, also signposts).
- **Video:** `simctl io recordVideo`; the analysis measures round trips away from the resting page, frozen runs
  inside transitions (stalls) and frames that appear and vanish (flashes).

## Targets

From frame-by-frame measurement of Arc on an iPhone 16 Pro: a page → switcher → page round trip in 300 ms,
no stalls, no flashes, no main-thread pass over 8 ms, no dropped frames.

## Physical device

`phonecap/phonecap.swift` records a USB-connected iPhone's screen with per-frame timestamps (build it into a
small app bundle with an `NSCameraUsageDescription` so macOS can grant it camera access). AXe also drives
physical devices. The simulator is the default loop; the device is for confirming.
