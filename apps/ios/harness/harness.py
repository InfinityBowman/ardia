#!/usr/bin/env python3
"""Ardia performance harness: drive the iOS app on a simulator, film it, and measure it.

  harness.py build                  Release build for the harness simulator, then install it
  harness.py launch [--tabs N]      Fresh launch on the fixture tabs with the probe on
  harness.py ui                     Accessibility elements on screen (label, centre)
  harness.py shot [file.png]        Screenshot
  harness.py run <scenario> [...]   Launch, perform the scenario while recording, analyse it
  harness.py analyse <run dir>      Re-run the analysis of an earlier run
  harness.py list                   Scenarios
  harness.py serve-media [--clip F]  Throttled video server on 127.0.0.1:8766 (video.html, hls.html)

Each run writes runs/<time>-<scenario>/ with video.mp4, probe.jsonl and report.json, and prints
the report. Nothing here needs a person: the simulator is driven with AXe (real HID touches that do
not wait for the app to go idle), and every fixture page is served locally so runs are comparable.
"""

import argparse
import datetime
import http.client
import json
import os
import shutil
import signal
import socket
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
IOS = os.path.dirname(HERE)
PROJECT = os.path.join(IOS, "Ardia.xcodeproj")
SIM_NAME = os.environ.get("ARDIA_HARNESS_SIM", "Ardia Harness")
BUNDLE = "com.jacobmaynard.ardia"
DERIVED = os.path.expanduser(os.environ.get("ARDIA_HARNESS_DERIVED", "~/Library/Caches/ardia-harness/DerivedData"))
APP = os.path.join(DERIVED, "Build/Products/Release-iphonesimulator/Ardia.app")
RUNS = os.path.join(HERE, "runs")
PORT = 8765
FIXTURES = f"http://127.0.0.1:{PORT}/"
MEDIA_PORT = 8766
MEDIA = f"http://127.0.0.1:{MEDIA_PORT}/"
VIDEO_FIXTURES = os.path.join(IOS, "Packages/ArdiaKit/Tests/ArdiaBrowserTests/Fixtures/Video")
DOWNLOAD_SECONDS = 12
BUSY_DOWNLOAD_SECONDS = 40

TARGETS = {
    "fall_ms": 450,
    "stall_frames": 0,
    "flash_frames": 0,
    "main_busy_max_ms": 16.7,
    "dropped_frames": 0,
    "tap_commit_ms": 8,
    "pager_first_move_ms": 40,
    "pager_settle_ms": 600,
    "misordered": 0,
    "ring_missing": 0,
    "ring_show_ms": 150,
    "wrong_submits": 0,
}

CHECKS = {
    "deck-rapid": ["fall_ms", "tap_commit_ms", "stall_frames", "flash_frames", "main_busy_max_ms", "dropped_frames"],
    "swipe-tabs": ["stall_frames", "flash_frames", "tap_commit_ms", "main_busy_max_ms", "dropped_frames", "pager_first_move_ms", "pager_settle_ms"],
    "swipe-interrupt": ["stall_frames", "flash_frames", "tap_commit_ms", "main_busy_max_ms", "dropped_frames", "pager_settle_ms"],
    "deck-turnback": ["misordered", "tap_commit_ms", "stall_frames", "flash_frames", "dropped_frames"],
    "download-ring": ["ring_missing", "ring_show_ms"],
    "download-scroll": ["ring_missing", "stall_frames", "main_busy_max_ms", "dropped_frames"],
    "idle-scroll": ["stall_frames", "main_busy_max_ms", "dropped_frames"],
    "download-swipe": ["ring_missing", "stall_frames", "main_busy_max_ms", "dropped_frames", "pager_first_move_ms", "pager_settle_ms"],
    "idle-swipe": ["stall_frames", "main_busy_max_ms", "dropped_frames", "pager_first_move_ms", "pager_settle_ms"],
    "typed-url": ["wrong_submits"],
}
LAUNCH_ARGS = {
    "swipe-interrupt": ["-BrowsePagerScript", "-BrowseDelay", "5"],
}
DEFAULT_CHECKS = ["stall_frames", "flash_frames", "tap_commit_ms", "main_busy_max_ms", "dropped_frames"]


def sh(cmd, check=True, capture=True, timeout=None):
    result = subprocess.run(cmd, check=False, capture_output=capture, text=True, timeout=timeout)
    if check and result.returncode != 0:
        sys.exit(f"command failed ({result.returncode}): {' '.join(cmd)}\n{result.stdout}\n{result.stderr}")
    return result


def udid():
    devices = json.loads(sh(["xcrun", "simctl", "list", "devices", "-j"]).stdout)["devices"]
    for runtime in devices.values():
        for device in runtime:
            if device["name"] == SIM_NAME and device.get("isAvailable", True):
                if device["state"] != "Booted":
                    sh(["xcrun", "simctl", "boot", device["udid"]], check=False)
                    sh(["xcrun", "simctl", "bootstatus", device["udid"], "-b"])
                return device["udid"]
    sys.exit(f'no simulator named "{SIM_NAME}"; create one with: xcrun simctl create "{SIM_NAME}" '
             "com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro com.apple.CoreSimulator.SimRuntime.iOS-27-2")


def build(args):
    sim = udid()
    started = time.time()
    log = os.path.join(os.path.dirname(DERIVED), "build.log")
    os.makedirs(os.path.dirname(log), exist_ok=True)
    with open(log, "w") as out:
        code = subprocess.call(["xcodebuild", "-project", PROJECT, "-scheme", "Ardia", "-configuration", "Release",
                                "-destination", f"id={sim}", "-derivedDataPath", DERIVED,
                                "COMPILER_INDEX_STORE_ENABLE=NO", "ONLY_ACTIVE_ARCH=YES", "-quiet", "build"], stdout=out, stderr=subprocess.STDOUT)
    errors = [l for l in open(log) if ": error:" in l]
    if code != 0 or "BUILD FAILED" in open(log).read():
        print("".join(sorted(set(errors))[:20]) or open(log).read()[-3000:])
        sys.exit("build failed")
    sh(["xcrun", "simctl", "install", sim, APP])
    print(f"built and installed in {time.time() - started:.0f}s")


def serve_fixtures():
    with socket.socket() as probe:
        if probe.connect_ex(("127.0.0.1", PORT)) == 0:
            return
    subprocess.Popen([sys.executable, "-m", "http.server", str(PORT), "--bind", "127.0.0.1",
                      "--directory", os.path.join(HERE, "fixtures")],
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
    for _ in range(50):
        try:
            http.client.HTTPConnection("127.0.0.1", PORT, timeout=0.2).request("HEAD", "/page-1.html")
            return
        except OSError:
            time.sleep(0.1)


VIDEO_PAGE = """<!doctype html><meta name=viewport content="width=device-width,initial-scale=1">
<title>Fixture Video</title><body style="margin:0;font:17px -apple-system;background:#fff;color:#222">
<video src="{src}" poster="/poster.svg" preload="none" controls playsinline style="width:100%;aspect-ratio:16/9;background:#333"></video>
<main style="padding:16px">{text}</main>"""


def media_page(src):
    text = "".join(f"<p>Paragraph {i}: a long fixture page to scroll while the video downloads.</p>" for i in range(160))
    return VIDEO_PAGE.format(src=src, text=text).encode()


POSTER = ('<svg xmlns="http://www.w3.org/2000/svg" width="320" height="180"><defs><linearGradient id="g" x1="0" x2="1">'
          '<stop offset="0" stop-color="#ff7a59"/><stop offset="1" stop-color="#6a5cff"/></linearGradient></defs>'
          '<rect width="320" height="180" fill="url(#g)"/><polygon points="140,60 140,120 190,90" fill="#fff"/></svg>').encode()


def serve_media_forever(args):
    import http.server
    import urllib.parse
    clip = args.clip or os.path.join(VIDEO_FIXTURES, "plain/clip.mp4")

    class Handler(http.server.BaseHTTPRequestHandler):
        protocol_version = "HTTP/1.1"

        def log_message(self, *a):
            pass

        def reply(self, body, kind, code=200, headers=()):
            self.send_response(code)
            self.send_header("Content-Type", kind)
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Cache-Control", "no-store")
            for k, v in headers:
                self.send_header(k, v)
            self.end_headers()
            if self.command != "HEAD":
                self.wfile.write(body)

        def do_HEAD(self):
            self.do_GET()

        def do_GET(self):
            url = urllib.parse.urlparse(self.path)
            query = dict(urllib.parse.parse_qsl(url.query))
            seconds = float(query.get("seconds", DOWNLOAD_SECONDS))
            if url.path == "/video.html":
                status = f"&status={query['status']}" if "status" in query else ""
                return self.reply(media_page(f"/clip.mp4?seconds={seconds:g}{status}"), "text/html; charset=utf-8")
            if url.path == "/hls.html":
                return self.reply(media_page(f"/hls/master.m3u8?seconds={seconds:g}"), "text/html; charset=utf-8")
            if url.path == "/poster.svg":
                return self.reply(POSTER, "image/svg+xml")
            if url.path == "/clip.mp4":
                if "status" in query:
                    return self.reply(b"gone", "text/plain", int(query["status"]))
                return self.send_throttled(open(clip, "rb").read(), seconds)
            if url.path.startswith("/hls/"):
                name = os.path.basename(url.path)
                path = os.path.join(VIDEO_FIXTURES, "fmp4", name)
                if not os.path.exists(path):
                    return self.reply(b"missing", "text/plain", 404)
                body = open(path, "rb").read()
                if name.endswith(".m3u8"):
                    return self.reply(body, "application/vnd.apple.mpegurl")
                time.sleep(seconds / 6)
                return self.reply(body, "video/mp4")
            return self.reply(b"missing", "text/plain", 404)

        def send_throttled(self, body, seconds):
            start, end = 0, len(body) - 1
            ranged = self.headers.get("Range", "")
            if ranged.startswith("bytes="):
                first, _, last = ranged[6:].partition("-")
                start = int(first or 0)
                end = int(last) if last else end
            part = body[start:end + 1]
            self.send_response(206 if ranged else 200)
            self.send_header("Content-Type", "video/mp4")
            self.send_header("Content-Length", str(len(part)))
            self.send_header("Accept-Ranges", "bytes")
            self.send_header("Cache-Control", "no-store")
            if ranged:
                self.send_header("Content-Range", f"bytes {start}-{end}/{len(body)}")
            self.end_headers()
            if self.command == "HEAD":
                return
            if len(part) < len(body) // 4 or self.headers.get("Sec-Fetch-Dest") == "video":
                self.wfile.write(part)
                return
            ticks = max(int(seconds * 20), 1)
            chunk = max(len(part) // ticks, 1)
            try:
                for offset in range(0, len(part), chunk):
                    self.wfile.write(part[offset:offset + chunk])
                    self.wfile.flush()
                    time.sleep(seconds / ticks)
            except (BrokenPipeError, ConnectionResetError):
                pass

    http.server.ThreadingHTTPServer(("127.0.0.1", MEDIA_PORT), Handler).serve_forever()


def serve_media():
    with socket.socket() as probe:
        if probe.connect_ex(("127.0.0.1", MEDIA_PORT)) == 0:
            return
    subprocess.Popen([sys.executable, os.path.abspath(__file__), "serve-media"],
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
    for _ in range(50):
        try:
            http.client.HTTPConnection("127.0.0.1", MEDIA_PORT, timeout=0.2).request("HEAD", "/poster.svg")
            return
        except OSError:
            time.sleep(0.1)


def probe_path(sim):
    container = sh(["xcrun", "simctl", "get_app_container", sim, BUNDLE, "data"]).stdout.strip()
    return os.path.join(container, "Documents/harness/probe.jsonl")


def read_probe(sim):
    path = probe_path(sim)
    if not os.path.exists(path):
        return []
    out = []
    for line in open(path):
        line = line.strip()
        if line:
            try:
                out.append(json.loads(line))
            except json.JSONDecodeError:
                pass
    return out


def launch(args, tabs=6, extra=(), launched=None):
    sim = udid()
    serve_fixtures()
    if any(str(a).startswith(MEDIA) for a in extra):
        serve_media()
    sh(["xcrun", "simctl", "terminate", sim, BUNDLE], check=False)
    sh(["xcrun", "simctl", "launch", sim, BUNDLE, "-ArdiaDemo", "-ArdiaProbe", "-ArdiaRestingStart",
        "-ArdiaHarnessSeed", FIXTURES, "-ArdiaHarnessTabs", str(tabs), "-BrowseSurface", "browsing", *extra])
    deadline = time.time() + 20
    while time.time() < deadline:
        if any(e.get("name") == "seed.done" for e in read_probe(sim) if e.get("k") == "m"):
            break
        time.sleep(0.2)
    settled = time.time() + 2.5
    if launched:
        launched(sim)
    time.sleep(max(0, settled - time.time()))
    return sim


def describe(sim):
    raw = sh(["axe", "describe-ui", "--udid", sim]).stdout
    data = json.loads(raw)
    found = []

    def walk(node):
        if isinstance(node, list):
            for child in node:
                walk(child)
            return
        if not isinstance(node, dict):
            return
        label = node.get("AXLabel") or node.get("label") or node.get("title")
        frame = node.get("frame") or node.get("AXFrame")
        if label and isinstance(frame, dict):
            found.append({"label": label, "type": node.get("type") or node.get("role"),
                          "x": frame["x"] + frame["width"] / 2, "y": frame["y"] + frame["height"] / 2,
                          "w": frame["width"], "h": frame["height"]})
        for key in ("children", "elements", "AXChildren"):
            if key in node:
                walk(node[key])

    walk(data)
    return found


def find(sim, label, exact=True):
    for element in describe(sim):
        if (element["label"] == label) if exact else (label.lower() in element["label"].lower()):
            return element
    return None


def ui(args):
    for element in describe(udid()):
        print(f'{element["label"][:50]:50s} {element["type"] or "":16s} ({element["x"]:.0f},{element["y"]:.0f}) {element["w"]:.0f}x{element["h"]:.0f}')


def shot(args):
    sim = udid()
    path = args.file or os.path.join(RUNS, "shot.png")
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    sh(["xcrun", "simctl", "io", sim, "screenshot", path])
    print(path)


def batch(sim, steps):
    if all(step.startswith("sleep ") for step in steps):
        time.sleep(sum(float(step.split()[1]) for step in steps))
        return
    sh(["axe", "batch", "--udid", sim, *sum((["--step", s] for s in steps), [])], timeout=600)


def scenario_deck_rapid(sim, cycles=8, out_gap=0.15, back_gap=0.25):
    """Tabs button, then the card you came from, as fast as Arc lets you (Arc: ~0.3 s per cycle)."""
    tabs = find(sim, "Tabs")
    if not tabs:
        sys.exit("no Tabs button on screen")
    batch(sim, [f"tap -x {tabs['x']:.0f} -y {tabs['y']:.0f}", "sleep 1.2"])
    selected = find(sim, "Fixture", exact=False)
    card = max((e for e in describe(sim) if e["label"].startswith("Fixture") and e["w"] > 150), key=lambda e: e["x"], default=selected)
    if not card:
        sys.exit("no tab card found in the switcher")
    batch(sim, [f"tap -x {card['x']:.0f} -y {card['y']:.0f}", "sleep 1.5"])
    steps = []
    for _ in range(cycles):
        steps += [f"tap -x {tabs['x']:.0f} -y {tabs['y']:.0f}", f"sleep {out_gap}",
                  f"tap -x {card['x']:.0f} -y {card['y']:.0f}", f"sleep {back_gap}"]
    steps.append("sleep 1.0")
    return steps


def scenario_deck_settled(sim, cycles=4):
    """Open the switcher, let it settle, tap the card, let the page settle."""
    return scenario_deck_rapid(sim, cycles=cycles, out_gap=0.9, back_gap=0.9)


def scenario_swipe_tabs(sim):
    """Swipe along the bottom bar between tabs, back and forth, then into the end of the order (rubber band)."""
    tabs = find(sim, "Tabs")
    y = tabs["y"] if tabs else 820
    flick = "--duration 0.12 --delta 6 --pre-delay 0 --post-delay 0"
    back = f"swipe --start-x 100 --start-y {y:.0f} --end-x 300 --end-y {y:.0f} {flick}"
    forward = f"swipe --start-x 300 --start-y {y:.0f} --end-x 100 --end-y {y:.0f} {flick}"
    steps = []
    for _ in range(3):
        steps += [back, "sleep 0.6"]
    for _ in range(5):
        steps += [forward, "sleep 0.6"]
    steps.append("sleep 1.0")
    return steps


def scenario_swipe_interrupt(sim):
    """The app's scripted pager run: a cancelled drag, a flick, a flick caught 120 ms into its settle and reversed (AXe cannot touch again that soon)."""
    return ["sleep 7.5"]


def scenario_deck_switch(sim, switches=4):
    """Open the switcher, tap the card to the left of the current one, repeat: lands on other tabs."""
    tabs = find(sim, "Tabs")
    if not tabs:
        sys.exit("no Tabs button on screen")
    steps = []
    for _ in range(switches):
        steps += [f"tap -x {tabs['x']:.0f} -y {tabs['y']:.0f}", "sleep 0.6", "tap -x 60 -y 470", "sleep 0.9"]
    steps.append("sleep 1.0")
    return steps


TURNBACK_GAPS = (0.05, 0.15, 0.3, 0.5)
TURNBACK_SCRIPT = ",".join(["wait:8"] + [f"switcher,wait:0.9,tap,wait:{gap},switcher,wait:1,browse,wait:1" for gap in TURNBACK_GAPS * 2])


def scenario_deck_turnback(sim):
    """In-app script (AXe taps are ~1 s apart, too slow to land mid-landing): open the switcher, open
    the card left of the current one, then the tabs button 50, 150, 300 ms into its landing and 500 ms
    after it began. The tapped tab must come back as the newest card, rightmost (Arc, SPEC 2.3 r3)."""
    return [f"sleep {len(TURNBACK_GAPS) * 2 * 3.0 + 6.0:.1f}"]


def scenario_search_toggle(sim, cycles=4):
    """Tap the address bar to search, then dismiss by tapping above the tray; the bar must stay put."""
    address = find(sim, "Address")
    if not address:
        sys.exit("no Address button on screen")
    steps = []
    for _ in range(cycles):
        steps += [f"tap -x {address['x']:.0f} -y {address['y']:.0f}", "sleep 0.7", "tap -x 200 -y 140", "sleep 0.9"]
    steps.append("sleep 1.0")
    return steps


def scenario_deck_pingpong(sim, cycles=8):
    """Tabs button again while the card is still landing (Arc reverses into the switcher)."""
    return scenario_deck_rapid(sim, cycles=cycles, out_gap=0.15, back_gap=0.08)


def scenario_deck_interrupt(sim, cycles=6, press=0.25):
    """Tap a card, then press the tabs button while it lands, lifting after the landing would end
    (a real finger is down ~100-250 ms). Every press must turn back into the switcher."""
    tabs = find(sim, "Tabs")
    if not tabs:
        sys.exit("no Tabs button on screen")
    x, y = tabs["x"], tabs["y"]
    batch(sim, [f"tap -x {x:.0f} -y {y:.0f}", "sleep 1.2"])
    card = max((e for e in describe(sim) if e["label"].startswith("Fixture") and e["w"] > 150), key=lambda e: e["x"], default=None)
    if not card:
        sys.exit("no tab card found in the switcher")
    steps = []
    for i in range(cycles):
        cx = card["x"] if i % 2 == 0 else 60
        steps += [f"tap -x {cx:.0f} -y {card['y']:.0f}", "sleep 0.04",
                  f"tap -x {x:.0f} -y {y:.0f} --hold {press}", "sleep 0.9"]
    steps.append("sleep 1.0")
    return steps


def scenario_deck_grid(sim, cycles=3):
    """Switcher, grid, stack, grid, open a tab from the grid; every bar button must answer."""
    tabs = find(sim, "Tabs")
    if not tabs:
        sys.exit("no Tabs button on screen")
    x, y = tabs["x"], tabs["y"]
    batch(sim, [f"tap -x {x:.0f} -y {y:.0f}", "sleep 1.2"])
    toggle = find(sim, "Show as Grid")
    if toggle:
        grid = [f"tap -x {toggle['x']:.0f} -y {toggle['y']:.0f}"]
    else:
        gear = find(sim, "Settings")
        if not gear:
            sys.exit("no grid toggle and no Settings button in the switcher")
        hold = f"touch -x {gear['x']:.0f} -y {gear['y']:.0f} --down --up --delay 0.7"
        batch(sim, [hold, "sleep 0.8"])
        item = find(sim, "Show as Grid")
        if not item:
            sys.exit("no Show as Grid item in the Settings button's menu")
        grid = [hold, "sleep 0.4", f"tap -x {item['x']:.0f} -y {item['y']:.0f}"]
        batch(sim, ["tap -x 200 -y 80", "sleep 0.6"])
    batch(sim, ["tap -x 200 -y 450", "sleep 1.2"])
    steps = []
    for _ in range(cycles):
        steps += [f"tap -x {x:.0f} -y {y:.0f}", "sleep 0.6", *grid, "sleep 0.5", *grid, "sleep 0.5", *grid, "sleep 0.5",
                  "tap -x 300 -y 500", "sleep 0.8"]
    steps.append("sleep 1.0")
    return steps


def scenario_search_plus(sim, cycles=3):
    """Tap + on the page for a new-tab search; the tray must ride up with the keyboard, not behind it."""
    plus = find(sim, "New Search") or find(sim, "Add")
    if not plus:
        sys.exit("no + button on screen")
    steps = []
    for _ in range(cycles):
        steps += [f"tap -x {plus['x']:.0f} -y {plus['y']:.0f}", "sleep 1.0", "tap -x 200 -y 140", "sleep 1.0"]
    steps.append("sleep 0.5")
    return steps


TYPED_URL = "http://127.0.0.1:8777/b.html"
TYPED_DELAYS = [1.0, 0.6, 0.35, 0.2]
TYPED_CYCLES = len(TYPED_DELAYS)


def scenario_typed_url(sim):
    """Type a full URL that shares a prefix with a history page and press Return, at several delays after opening search; it must submit exactly what was typed."""
    plus = find(sim, "New Search") or find(sim, "Add")
    if not plus:
        sys.exit("no + button on screen")
    for delay in TYPED_DELAYS:
        batch(sim, [f"tap -x {plus['x']:.0f} -y {plus['y']:.0f}", f"sleep {delay}"])
        sh(["axe", "type", TYPED_URL, "--udid", sim])
        sh(["axe", "key", "40", "--udid", sim])
        time.sleep(1.5)
    return ["sleep 0.5"]


def analyse_submits(events, scenario):
    if scenario != "typed-url":
        return {}
    submits = [e.get("detail", "") for e in events if e.get("k") == "m" and e.get("name") == "search.submit"]
    wrong = sum(1 for s in submits if s != TYPED_URL) + max(TYPED_CYCLES - len(submits), 0)
    return {"submitted": submits, "wrong": wrong}


def scenario_page_menu(sim, cycles=2):
    """Tap ^ for the page menu, close it by tapping the page, then open it again and swipe it down."""
    more = find(sim, "Page Menu")
    if not more:
        sys.exit("no page menu button on screen")
    tap = f"tap -x {more['x']:.0f} -y {more['y']:.0f}"
    steps = []
    for _ in range(cycles):
        steps += [tap, "sleep 1.0", "tap -x 200 -y 140", "sleep 1.0"]
        steps += [tap, "sleep 1.0", "swipe --start-x 200 --start-y 560 --end-x 200 --end-y 800 --duration 0.12", "sleep 1.0"]
    steps.append("sleep 0.5")
    return steps


def scenario_display_options(sim):
    """Open the page menu, expand and collapse Display Options twice at rest, then tap it six times 0.2 s apart."""
    more = find(sim, "Page Menu")
    if not more:
        sys.exit("no page menu button on screen")
    batch(sim, [f"tap -x {more['x']:.0f} -y {more['y']:.0f}", "sleep 1.0"])
    row = find(sim, "Display Options")
    if not row:
        sys.exit("no Display Options row in the page menu")
    if (row.get("value") or "") == "Expanded" or find(sim, "Translate"):
        batch(sim, [f"tap -x {row['x']:.0f} -y {row['y']:.0f}", "sleep 1.0"])
        row = find(sim, "Display Options")
    tap = f"tap -x {row['x']:.0f} -y {row['y']:.0f}"
    steps = []
    for _ in range(2):
        steps += [tap, "sleep 1.0", f"tap -x {row['x']:.0f} -y {row['y'] - 194:.0f}", "sleep 1.0"]
    for _ in range(3):
        steps += [tap, "sleep 0.2", f"tap -x {row['x']:.0f} -y {row['y'] - 194:.0f}", "sleep 0.2"]
    steps.append("sleep 1.0")
    return steps


def scenario_more_options(sim):
    """Open the page menu, expand and collapse More twice at rest, then twice 0.2 s apart."""
    more = find(sim, "Page Menu")
    if not more:
        sys.exit("no page menu button on screen")
    batch(sim, [f"tap -x {more['x']:.0f} -y {more['y']:.0f}", "sleep 1.0"])
    row = find(sim, "More")
    if not row:
        sys.exit("no More row in the page menu")
    batch(sim, [f"tap -x {row['x']:.0f} -y {row['y']:.0f}", "sleep 1.0"])
    open_row = find(sim, "More")
    batch(sim, [f"tap -x {open_row['x']:.0f} -y {open_row['y']:.0f}", "sleep 1.0"])
    shut = f"tap -x {row['x']:.0f} -y {row['y']:.0f}"
    opened = f"tap -x {open_row['x']:.0f} -y {open_row['y']:.0f}"
    steps = []
    for _ in range(2):
        steps += [shut, "sleep 1.0", opened, "sleep 1.0"]
    for _ in range(2):
        steps += [shut, "sleep 0.2", opened, "sleep 0.2"]
    steps.append("sleep 1.0")
    return steps


def scenario_deck_close(sim, closes=3):
    """Open the switcher, flick the focused card up to close it, three times; the deck reflows each time."""
    tabs = find(sim, "Tabs")
    if not tabs:
        sys.exit("no Tabs button on screen")
    batch(sim, [f"tap -x {tabs['x']:.0f} -y {tabs['y']:.0f}", "sleep 1.2"])
    flick = "swipe --start-x 200 --start-y 560 --end-x 200 --end-y 260 --duration 0.12 --delta 10 --pre-delay 0 --post-delay 0"
    steps = []
    for _ in range(closes):
        steps += [flick, "sleep 0.9"]
    steps.append("sleep 0.5")
    return steps


SURFACES_SCRIPT = ",".join(["wait:8", "switcher", "wait:1", "archive", "wait:1.2", "dismiss", "wait:1.2", "browse", "wait:1",
                            "incognito", "wait:1.5", "browse", "wait:1.2", "switcher", "wait:1", "empty", "wait:1.5", "home", "wait:1.5"])


def scenario_deck_surfaces(sim):
    """In-app script: switcher, Archive up and down, back to the page, Incognito's switcher, the empty switcher, the start page."""
    return ["sleep 21"]


def held_drag(x0, x1, y, hold):
    steps = max(int(abs(x1 - x0) / 10), 2)
    points = [(x0 + (x1 - x0) * k / steps, y) for k in range(steps + 1)]
    points += [(x1, y + (0.5 if k % 2 == 0 else 0)) for k in range(hold)]
    return " ".join(f"{a:.1f},{b:.1f}" for a, b in points)


def scenario_page_swipe(sim):
    """Open Swipe B from Swipe A, then flick back, flick forward, drag back 60 % and lift at rest (Arc cancels),
    drag back 15 % slowly and lift while moving (Arc commits), then swipe in from each screen edge with no
    history that way, which turns to the neighbouring tab as Arc's does."""
    batch(sim, ["tap -x 200 -y 320", "sleep 2.5"])
    flick = "--duration 0.15 --delta 8 --pre-delay 0 --post-delay 0"
    return [f"swipe --start-x 80 --start-y 520 --end-x 330 --end-y 520 {flick}", "sleep 1.5",
            f"swipe --start-x 330 --start-y 520 --end-x 80 --end-y 520 {flick}", "sleep 1.5",
            f"draw {held_drag(40, 280, 520, 80)} --duration 1.6", "sleep 1.5",
            "draw 40,520 60,520 80,520 100,520 --duration 0.9", "sleep 2.0",
            f"swipe --start-x 1 --start-y 520 --end-x 260 --end-y 520 {flick}", "sleep 1.5",
            f"swipe --start-x 401 --start-y 520 --end-x 140 --end-y 520 {flick}", "sleep 1.5"]


def scenario_page_swipe_script(sim):
    """Open Script B from Script A with pushState, then flick back and forward: both swipes must slide a picture
    of the page they land on, never a blank one."""
    batch(sim, ["tap -x 200 -y 320", "sleep 2.5"])
    flick = "--duration 0.15 --delta 8 --pre-delay 0 --post-delay 0"
    return [f"swipe --start-x 80 --start-y 520 --end-x 330 --end-y 520 {flick}", "sleep 1.5",
            f"swipe --start-x 330 --start-y 520 --end-x 80 --end-y 520 {flick}", "sleep 1.5"]


def start_download(sim):
    more = find(sim, "Page Menu")
    if not more:
        sys.exit("no page menu button on screen")
    tap = f"tap -x {more['x']:.0f} -y {more['y']:.0f}"
    batch(sim, [tap, "sleep 1.0"])
    row = find(sim, "Download Video")
    batch(sim, ["tap -x 200 -y 140", "sleep 0.8"])
    if not row:
        sys.exit("no Download Video row in the page menu")
    return [tap, "sleep 0.8", f"tap -x {row['x']:.0f} -y {row['y']:.0f}"]


def scenario_download_ring(sim):
    """Tap ^, Download Video on a throttled mp4 (~12 s): the ring must show at once, end in a check and clear."""
    return start_download(sim) + [f"sleep {DOWNLOAD_SECONDS + 5}"]


def scroll_steps():
    down = "swipe --start-x 200 --start-y 650 --end-x 200 --end-y 250 --duration 0.25 --delta 8 --pre-delay 0 --post-delay 0"
    up = "swipe --start-x 200 --start-y 250 --end-x 200 --end-y 650 --duration 0.25 --delta 8 --pre-delay 0 --post-delay 0"
    steps = []
    for _ in range(4):
        steps += [down, "sleep 0.7"]
    for _ in range(4):
        steps += [up, "sleep 0.7"]
    steps.append("sleep 1.0")
    return steps


TOAST_CLEAR = "sleep 3.5"


def open_and_close_menu(sim):
    more = find(sim, "Page Menu")
    if not more:
        sys.exit("no page menu button on screen")
    batch(sim, [f"tap -x {more['x']:.0f} -y {more['y']:.0f}", "sleep 1.0", "tap -x 200 -y 140", "sleep 0.8",
                f"tap -x {more['x']:.0f} -y {more['y']:.0f}", "sleep 0.8", "tap -x 200 -y 140", TOAST_CLEAR])


def scenario_idle_scroll(sim):
    """Scroll the video fixture page down and back up with no download running (control for download-scroll)."""
    open_and_close_menu(sim)
    return scroll_steps()


def scenario_download_scroll(sim):
    """Start a throttled download, then scroll the page down and up while the ring runs."""
    batch(sim, start_download(sim) + [TOAST_CLEAR])
    return scroll_steps()


def scenario_idle_swipe(sim):
    """swipe-tabs on the fixture tabs plus the video tab, no download (control for download-swipe)."""
    open_and_close_menu(sim)
    return scenario_swipe_tabs(sim)


def scenario_download_swipe(sim):
    """Start a throttled download, then swipe-tabs along the bar while the ring runs."""
    batch(sim, start_download(sim) + [TOAST_CLEAR])
    return scenario_swipe_tabs(sim)


SCENARIOS = {
    "download-ring": scenario_download_ring,
    "idle-scroll": scenario_idle_scroll,
    "download-scroll": scenario_download_scroll,
    "idle-swipe": scenario_idle_swipe,
    "download-swipe": scenario_download_swipe,
    "search-plus": scenario_search_plus,
    "page-menu": scenario_page_menu,
    "deck-rapid": scenario_deck_rapid,
    "deck-pingpong": scenario_deck_pingpong,
    "deck-grid": scenario_deck_grid,
    "deck-interrupt": scenario_deck_interrupt,
    "deck-settled": scenario_deck_settled,
    "swipe-tabs": scenario_swipe_tabs,
    "swipe-interrupt": scenario_swipe_interrupt,
    "deck-switch": scenario_deck_switch,
    "search-toggle": scenario_search_toggle,
    "deck-turnback": scenario_deck_turnback,
    "deck-close": scenario_deck_close,
    "deck-surfaces": scenario_deck_surfaces,
    "page-swipe": scenario_page_swipe,
    "page-swipe-script": scenario_page_swipe_script,
    "display-options": scenario_display_options,
    "more-options": scenario_more_options,
    "typed-url": scenario_typed_url,
}
LAUNCH_ARGS["deck-turnback"] = ["-ArdiaDeck", TURNBACK_SCRIPT]
LAUNCH_ARGS["deck-surfaces"] = ["-ArdiaDeck", SURFACES_SCRIPT]
LAUNCH_ARGS["page-swipe"] = ["-ArdiaHarnessOpen", f"{FIXTURES}nav-a.html"]
LAUNCH_ARGS["page-swipe-script"] = ["-ArdiaHarnessOpen", f"{FIXTURES}spa-a.html"]
LAUNCH_ARGS["download-ring"] = ["-ArdiaHarnessOpen", f"{MEDIA}video.html?seconds={DOWNLOAD_SECONDS}"]
for _name in ("idle-scroll", "download-scroll", "idle-swipe", "download-swipe"):
    LAUNCH_ARGS[_name] = ["-ArdiaHarnessOpen", f"{MEDIA}video.html?seconds={BUSY_DOWNLOAD_SECONDS}"]


def video_frames(path, w=60, h=130):
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", path, "-vf", f"scale={w}:{h},format=gray", "-f", "rawvideo",
                          "-fps_mode", "passthrough", "-"], capture_output=True, check=True).stdout
    pts = [float(x.strip().strip(",")) for x in sh(["ffprobe", "-v", "error", "-select_streams", "v", "-show_entries",
                                                  "frame=pts_time", "-of", "csv=p=0", path]).stdout.split() if x.strip().strip(",")]
    size = w * h
    frames = [raw[i * size:(i + 1) * size] for i in range(len(raw) // size)]
    return frames, pts[:len(frames)], w, h


def analyse_video(path):
    frames, pts, w, h = video_frames(path)
    if len(frames) < 3:
        return {"error": "no video frames"}
    top, bottom = int(h * 0.08), int(h * 0.85)
    span = range(top * w, bottom * w, 2)

    def dist(a, b):
        return sum(abs(a[k] - b[k]) for k in span) / len(span)

    rest = frames[0]
    away = [dist(f, rest) for f in frames]
    move = [0.0] + [dist(frames[i], frames[i - 1]) for i in range(1, len(frames))]
    at_rest = [d < 3 for d in away]
    trips, start = [], None
    for i, resting in enumerate(at_rest):
        if not resting and start is None:
            start = i
        elif resting and start is not None:
            trips.append((start, i))
            start = None
    stalls, flashes = [], []
    for a, b in trips:
        i = a
        while i < b:
            if move[i] < 0.5:
                j = i
                while j < b and move[j] < 0.5:
                    j += 1
                frozen = pts[j] - pts[i]
                if 0.030 <= frozen < 0.35 and j < b:
                    stalls.append({"at": round(pts[i], 3), "ms": round((pts[j] - pts[i]) * 1000), "away": round(away[i], 1)})
                i = j
            else:
                i += 1
    for i in range(1, len(frames) - 3):
        if move[i] < 8:
            continue
        for k in (1, 2, 3):
            if dist(frames[i - 1], frames[i + k]) < 3 and move[i + k] > 8:
                flashes.append({"at": round(pts[i], 3), "frames": k})
                break
    durations = [round((pts[b] - pts[a]) * 1000) for a, b in trips]
    rises, falls = [], []
    for a, b in trips:
        peak = max(range(a, b), key=lambda i: away[i])
        rises.append(round((pts[peak] - pts[a]) * 1000))
        falls.append(round((pts[b] - pts[peak]) * 1000))
    median = lambda xs: sorted(xs)[len(xs) // 2] if xs else None
    return {
        "frames": len(frames),
        "seconds": round(pts[-1] - pts[0], 2),
        "round_trips_ms": durations,
        "round_trip_median_ms": median(durations),
        "rise_ms": rises,
        "fall_ms": falls,
        "fall_median_ms": median(falls),
        "stalls": stalls,
        "stall_frames_total_ms": sum(s["ms"] for s in stalls),
        "flashes": flashes,
    }


def window_start(events, meta):
    start = next((e for e in events if e.get("k") == "start"), {})
    if "window_start_wall" in meta and "wall" in start:
        return start["t"] + (meta["window_start_wall"] - start["wall"])
    return None


def analyse_probe(events, t0=None):
    if t0 is not None:
        events = [e for e in events if e.get("k") == "start" or (e.get("t") or e.get("ts") or e.get("s") or 0) >= t0]
    start = next((e for e in events if e.get("k") == "start"), {})
    fps = start.get("maxFPS", 60)
    frame = 1.0 / fps
    ticks = [e for e in events if e.get("k") == "f"]
    marks = [e for e in events if e.get("k") == "m"]
    busy = [e for e in events if e.get("k") == "busy"]
    interaction = [m for m in marks if m["name"] not in ("seed.done",)]
    first = interaction[0]["t"] - 0.2 if interaction else 0
    dropped, late = 0, []
    for a, b in zip(ticks, ticks[1:]):
        if a["ts"] < first:
            continue
        gap = b["ts"] - a["ts"]
        missed = round(gap / frame) - 1
        if missed > 0:
            dropped += missed
            late.append({"at": round(a["ts"], 3), "missed": missed})
    passes = sorted(((e["e"] - e["s"]) * 1000, e["s"], e["e"]) for e in busy if e["s"] >= first)
    worst = []
    for ms, s, e in reversed(passes[-12:]):
        near = [m["name"] + (f"({m['detail']})" if m.get("detail") else "") for m in marks if s - 0.05 <= m["t"] <= e]
        worst.append({"ms": round(ms, 1), "at": round(s, 3), "during": near})
    latencies = {}

    def pair(a, b, key):
        out = []
        for m in marks:
            if m["name"] == a:
                nxt = next((n for n in marks if n["name"] == b and n["t"] >= m["t"]), None)
                if nxt:
                    out.append(round((nxt["t"] - m["t"]) * 1000, 1))
        if out:
            latencies[key] = out

    for name in ("tabs.tap", "deck.cardTap", "search.open", "search.close", "pager.begin", "pager.settle"):
        values = []
        for m in marks:
            if m["name"] != name:
                continue
            committed = next((n for n in marks if n["name"] == "anim.committed" and m["t"] <= n["t"] <= m["t"] + 0.2), None)
            if committed:
                values.append(round((committed["t"] - m["t"]) * 1000, 1))
                continue
            pass_ = next((b for b in busy if b["s"] <= m["t"] <= b["e"]), None)
            values.append(round((pass_["e"] - m["t"]) * 1000, 1) if pass_ else 0.0)
        if values:
            latencies[f"{name}->commit_ms"] = values
    pair("tabs.tap", "deck.appear", "tabs.tap->deck.appear_ms")
    pair("tabs.tap", "deck.present", "tabs.tap->deck.present_ms")
    pair("deck.cardTap", "deck.closed", "deck.cardTap->deck.closed_ms")
    pair("deck.cardTap", "openTab", "deck.cardTap->openTab_ms")
    pair("deck.return", "openTab", "deck.return->openTab_ms")
    pair("search.open", "keyboard.willShow", "search.open->keyboard_ms")
    keyboard_passes = []
    for m in marks:
        if m["name"] != "search.open":
            continue
        shown = next((n for n in marks if n["name"] == "keyboard.willShow" and n["t"] >= m["t"]), None)
        if shown:
            inside = [(e["e"] - e["s"]) * 1000 for e in busy if e["e"] >= m["t"] - 0.05 and e["s"] <= shown["t"]]
            keyboard_passes.append(round(max(inside, default=0), 1))
    if keyboard_passes:
        latencies["search.open->keyboard_worst_pass_ms"] = keyboard_passes
    touches = [e["t"] for e in events if e.get("k") == "touch" and e.get("phase") == "began"]
    first_moves = []
    for m in marks:
        if m["name"] == "pager.move":
            down = max((t for t in touches if t <= m["t"]), default=None)
            if down is not None:
                first_moves.append(round((m["t"] - down) * 1000, 1))
    if first_moves:
        latencies["touch->pager.move_ms"] = first_moves
    finger = [e["t"] for e in events if e.get("k") == "touch" and e.get("phase") == "moved"]
    follow = []
    for m in marks:
        if m["name"] == "pager.move":
            moved = max((t for t in finger if t <= m["t"]), default=None)
            if moved is not None:
                follow.append(round((m["t"] - moved) * 1000, 1))
    if follow:
        latencies["finger.move->pager.move_ms"] = follow
    settles = []
    for i, m in enumerate(marks):
        if m["name"] != "pager.settle":
            continue
        nxt = next((n for n in marks[i + 1:] if n["name"] in ("pager.settled", "pager.catch", "pager.settle")), None)
        if nxt and nxt["name"] == "pager.settled":
            settles.append(round((nxt["t"] - m["t"]) * 1000, 1))
    if settles:
        latencies["pager.settle->settled_ms"] = settles
    return {
        "display_fps": fps,
        "dropped_frames": dropped,
        "late_frames": late[:20],
        "main_busy_max_ms": round(passes[-1][0], 1) if passes else 0,
        "main_busy_over_16ms": sum(1 for p in passes if p[0] > 16),
        "worst_main_passes": worst,
        "latencies": latencies,
        "marks": [{"t": round(m["t"], 3), "name": m["name"], **({"detail": m["detail"]} if m.get("detail") else {})} for m in interaction][:80],
        "misordered": sum(1 for m in marks if m["name"] == "deck.misordered"),
    }


def analyse_ring(events, scenario):
    marks = [e for e in events if e.get("k") == "m"]
    ups = [e["t"] for e in events if e.get("k") == "touch" and e.get("phase") == "ended"]
    shows = [m["t"] for m in marks if m["name"] == "ring.show"]
    dones = [m["t"] for m in marks if m["name"] == "ring.done"]
    clears = [m["t"] for m in marks if m["name"] == "ring.clear"]
    out = {"show": [round(t, 3) for t in shows], "done": [round(t, 3) for t in dones], "clear": [round(t, 3) for t in clears],
           "finished": sum(1 for m in marks if m["name"] == "download.finished"),
           "failed": sum(1 for m in marks if m["name"] == "download.failed")}
    if shows:
        up = max((t for t in ups if t <= shows[0]), default=None)
        out["touch_up_to_show_ms"] = round((shows[0] - up) * 1000, 1) if up is not None else None
    if scenario == "download-ring":
        out["missing"] = sum([not shows, not (dones and out["finished"]), not (dones and any(c > dones[-1] for c in clears))])
    elif scenario.startswith("download-"):
        out["missing"] = (0 if shows else 1) + (0 if not out["failed"] else 1)
    return out


def verdict(report):
    v = report.get("video", {})
    p = report.get("probe", {})
    ring = report.get("ring", {})
    checks = {
        "fall_ms": (v.get("fall_median_ms"), TARGETS["fall_ms"]),
        "stall_frames": (len(v.get("stalls", [])), TARGETS["stall_frames"]),
        "flash_frames": (len(v.get("flashes", [])), TARGETS["flash_frames"]),
        "main_busy_max_ms": (p.get("main_busy_max_ms"), TARGETS["main_busy_max_ms"]),
        "dropped_frames": (p.get("dropped_frames"), TARGETS["dropped_frames"]),
        "tap_commit_ms": (max([v for k, vs in p.get("latencies", {}).items() if k.endswith("->commit_ms") for v in vs], default=None), TARGETS["tap_commit_ms"]),
        "pager_first_move_ms": (max(p.get("latencies", {}).get("touch->pager.move_ms", []), default=None), TARGETS["pager_first_move_ms"]),
        "pager_settle_ms": (max(p.get("latencies", {}).get("pager.settle->settled_ms", []), default=None), TARGETS["pager_settle_ms"]),
        "misordered": (p.get("misordered"), TARGETS["misordered"]),
        "ring_missing": (ring.get("missing"), TARGETS["ring_missing"]),
        "ring_show_ms": (ring.get("touch_up_to_show_ms"), TARGETS["ring_show_ms"]),
        "wrong_submits": (report.get("submits", {}).get("wrong"), TARGETS["wrong_submits"]),
    }
    wanted = CHECKS.get(report.get("scenario"), DEFAULT_CHECKS)
    return {k: {"value": val, "target": tgt, "ok": val is not None and val <= tgt} for k, (val, tgt) in checks.items() if k in wanted}


def summarise(report):
    v, p = report.get("video", {}), report.get("probe", {})
    print(f"\n== {report['scenario']}  ({report['dir']})")
    for key, check in report["verdict"].items():
        print(f"  {'PASS' if check['ok'] else 'FAIL'}  {key:18s} {check['value']!s:>8}  (target <= {check['target']})")
    print(f"  round trips (ms): {v.get('round_trips_ms')}")
    print(f"  rise (ms): {v.get('rise_ms')}   fall (ms): {v.get('fall_ms')}")
    print(f"  stalls: {v.get('stalls')}")
    print(f"  flashes: {v.get('flashes')}")
    print(f"  dropped frames: {p.get('dropped_frames')} at {p.get('display_fps')} fps; main passes > 16 ms: {p.get('main_busy_over_16ms')}")
    for w in p.get("worst_main_passes", [])[:6]:
        print(f"    main busy {w['ms']:6.1f} ms at {w['at']}  {', '.join(w['during'])}")
    for key, values in p.get("latencies", {}).items():
        print(f"  {key}: {values}")
    if report.get("ring", {}).get("show"):
        print(f"  ring: {report['ring']}")
    if report.get("submits"):
        print(f"  submits: {report['submits']}")
    for slow in report.get("trace") or []:
        if isinstance(slow, dict) and slow.get("samples"):
            print(f"\n  -- main pass {slow['ms']} ms at {slow['at']} ({slow['samples']} samples)")
            for line in slow["ardia"][:8]:
                print(f"     {line}")
            generic = ("CFRunLoop", "__CF", "GSEvent", "UIApplicationMain", "$main", "start_sim", "_UIUpdateSequence",
                       "schedulerStep", "UC::Driver", "dispatch", "mach_msg", "UIApplication")
            for line in [l for l in slow["inclusive"] if not any(g in l for g in generic)][:10]:
                print(f"     . {line}")


def analyse_trace(directory, events, t0=None):
    trace = os.path.join(directory, "trace.trace")
    if not os.path.exists(trace):
        return None
    xml_path = os.path.join(directory, "time-profile.xml")
    if not os.path.exists(xml_path):
        sh(["xcrun", "xctrace", "export", "--input", trace, "--xpath",
            '/trace-toc/run[@number="1"]/data/table[@schema="time-profile"]', "--output", xml_path], check=False)
    toc = sh(["xcrun", "xctrace", "export", "--input", trace, "--toc"], check=False).stdout
    import re
    import xml.etree.ElementTree as ET
    started = re.search(r"<start-date>([^<]+)</start-date>", toc)
    start = next((e for e in events if e.get("k") == "start"), None)
    if not started or not start or "wall" not in start or not os.path.exists(xml_path):
        return {"error": "trace could not be aligned"}
    trace_wall = datetime.datetime.fromisoformat(started.group(1).replace("Z", "+00:00")).timestamp()
    offset = start["t"] - (start["wall"] - trace_wall)
    root = ET.parse(xml_path).getroot()
    node = root.find("node")
    cols = [c.find("mnemonic").text for c in node.find("schema").findall("col")]
    ids = {}

    def reg(e):
        if "id" in e.attrib:
            ids[e.attrib["id"]] = e
        for c in e:
            reg(c)

    def res(e):
        return ids[e.attrib["ref"]] if "ref" in e.attrib else e

    samples = []
    for r in node.findall("row"):
        reg(r)
        d = dict(zip(cols, [res(e) for e in r]))
        thread = d.get("thread")
        name = thread.attrib.get("fmt", "") if thread is not None else ""
        if "Main Thread" not in name:
            continue
        frames = []
        for f in res(d["stack"]).iter("frame"):
            f = res(f)
            b = f.find("binary")
            b = res(b).attrib.get("name", "?") if b is not None else "?"
            frames.append((f.attrib.get("name", "?"), b))
        samples.append((offset + int(d["time"].text) / 1e9, frames))
    busy = sorted(((e["e"] - e["s"]), e["s"], e["e"]) for e in events if e.get("k") == "busy" and (t0 is None or e["s"] >= t0))
    noise = {"main", "start", "<deduplicated_symbol>", "static App.main()", "runApp<A>(_:)", "closure #1 in KitRendererCommon(_:)"}
    report = []
    for duration, s, e in reversed(busy[-8:]):
        inside = [f for t, f in samples if s <= t <= e]
        own, inclusive, leaf = {}, {}, {}
        for frames in inside:
            if frames:
                key = f"{frames[0][0]} [{frames[0][1]}]"
                leaf[key] = leaf.get(key, 0) + 1
            seen = set()
            for name, binary in frames:
                if name in noise or name in seen:
                    continue
                seen.add(name)
                key = f"{name[:110]} [{binary}]"
                inclusive[key] = inclusive.get(key, 0) + 1
                if "Ardia" in binary:
                    own[key] = own.get(key, 0) + 1
        top = lambda d, n: [f"{c:4d} {k}" for k, c in sorted(d.items(), key=lambda x: -x[1])[:n]]
        if not inside:
            continue
        report.append({"ms": round(duration * 1000, 1), "at": round(s, 3), "samples": len(inside),
                       "ardia": top(own, 10), "inclusive": top(inclusive, 40), "leaf": top(leaf, 5)})
    return report


def analyse(args, directory=None, scenario=None):
    directory = directory or args.dir
    meta = json.load(open(os.path.join(directory, "meta.json"))) if os.path.exists(os.path.join(directory, "meta.json")) else {}
    events = [json.loads(l) for l in open(os.path.join(directory, "probe.jsonl")) if l.strip()] if os.path.exists(os.path.join(directory, "probe.jsonl")) else []
    t0 = window_start(events, meta)
    report = {"scenario": scenario or meta.get("scenario", "?"), "dir": directory,
              "video": analyse_video(os.path.join(directory, "video.mp4")), "probe": analyse_probe(events, t0)}
    report["ring"] = analyse_ring(events, report["scenario"])
    report["submits"] = analyse_submits(events, report["scenario"])
    report["verdict"] = verdict(report)
    report["trace"] = analyse_trace(directory, events, t0)
    json.dump(report, open(os.path.join(directory, "report.json"), "w"), indent=2)
    summarise(report)
    return report


def run(args):
    if args.scenario not in SCENARIOS:
        sys.exit(f"unknown scenario; choose from {', '.join(SCENARIOS)}")
    stamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
    directory = os.path.join(RUNS, f"{stamp}-{args.scenario}")
    os.makedirs(directory, exist_ok=True)
    tracers = []

    def start_tracer(sim):
        listing = sh(["xcrun", "simctl", "spawn", sim, "launchctl", "list"]).stdout
        pid = next((line.split()[0] for line in listing.splitlines() if BUNDLE in line and line.split()[0].isdigit()), None)
        if pid:
            tracers.append(subprocess.Popen(["xcrun", "xctrace", "record", "--template", "Time Profiler", "--device", sim,
                                             "--attach", pid, "--output", os.path.join(directory, "trace.trace")],
                                            stdout=open(os.path.join(directory, "trace.log"), "w"), stderr=subprocess.STDOUT))
            deadline = time.time() + 8
            while time.time() < deadline and "Ctrl-C" not in open(os.path.join(directory, "trace.log")).read():
                time.sleep(0.1)

    sim = launch(args, tabs=args.tabs, extra=LAUNCH_ARGS.get(args.scenario, ()), launched=start_tracer if args.trace else None)
    steps = SCENARIOS[args.scenario](sim)
    video = os.path.join(directory, "video.mp4")
    recorder = subprocess.Popen(["xcrun", "simctl", "io", sim, "recordVideo", "--codec=h264", "--force", video],
                                stdout=subprocess.DEVNULL, stderr=open(os.path.join(directory, "recorder.log"), "w"))
    tracer = tracers[0] if tracers else None
    deadline = time.time() + 15
    while time.time() < deadline and "Recording started" not in open(os.path.join(directory, "recorder.log")).read():
        time.sleep(0.1)
    time.sleep(1.0)
    began = time.time()
    batch(sim, steps)
    time.sleep(0.5)
    recorder.send_signal(signal.SIGINT)
    recorder.wait(timeout=30)
    if tracer:
        tracer.send_signal(signal.SIGINT)
        tracer.wait(timeout=180)
    shutil.copy(probe_path(sim), os.path.join(directory, "probe.jsonl"))
    json.dump({"scenario": args.scenario, "steps": steps, "batch_seconds": round(time.time() - began, 2), "tabs": args.tabs,
               "window_start_wall": began},
              open(os.path.join(directory, "meta.json"), "w"), indent=2)
    return analyse(args, directory, args.scenario)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("build").set_defaults(func=build)
    p = sub.add_parser("launch")
    p.add_argument("--tabs", type=int, default=6)
    p.set_defaults(func=lambda a: launch(a, tabs=a.tabs))
    sub.add_parser("ui").set_defaults(func=ui)
    p = sub.add_parser("shot")
    p.add_argument("file", nargs="?")
    p.set_defaults(func=shot)
    p = sub.add_parser("run")
    p.add_argument("scenario")
    p.add_argument("--tabs", type=int, default=6)
    p.add_argument("--trace", action="store_true", help="also record a Time Profiler trace and attribute slow passes")
    p.set_defaults(func=run)
    p = sub.add_parser("video", help="analyse any screen recording, e.g. of another browser")
    p.add_argument("file")
    p.set_defaults(func=lambda a: print(json.dumps({k: v for k, v in analyse_video(a.file).items() if k not in ("stalls",)}, indent=1)))
    p = sub.add_parser("analyse")
    p.add_argument("dir")
    p.set_defaults(func=analyse)
    p = sub.add_parser("serve-media")
    p.add_argument("--clip", help="mp4 to serve as /clip.mp4 (default: the ArdiaKit fixture clip)")
    p.set_defaults(func=serve_media_forever)
    sub.add_parser("list").set_defaults(func=lambda a: [print(f"{k:14s} {v.__doc__}") for k, v in SCENARIOS.items()])
    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
