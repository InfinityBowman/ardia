#!/usr/bin/env python3
"""Ardia performance harness: drive the iOS app on a simulator, film it, and measure it.

  harness.py build                  Release build for the harness simulator, then install it
  harness.py launch [--tabs N]      Fresh launch on the fixture tabs with the probe on
  harness.py ui                     Accessibility elements on screen (label, centre)
  harness.py shot [file.png]        Screenshot
  harness.py run <scenario> [...]   Launch, perform the scenario while recording, analyse it
  harness.py analyse <run dir>      Re-run the analysis of an earlier run
  harness.py list                   Scenarios

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
SIM_NAME = "Ardia Harness"
BUNDLE = "com.jacobmaynard.ardia"
DERIVED = os.path.expanduser("~/Library/Caches/ardia-harness/DerivedData")
APP = os.path.join(DERIVED, "Build/Products/Release-iphonesimulator/Ardia.app")
RUNS = os.path.join(HERE, "runs")
PORT = 8765
FIXTURES = f"http://127.0.0.1:{PORT}/"

# What "as quick as Arc" means, from frame-by-frame measurement of Arc on an iPhone 16 Pro.
TARGETS = {
    "fall_ms": 450,            # tap on the card -> page fully back. Arc snaps in ~150-170 ms; Jacob found that too fast, so the landing is 0.34 s (interruptible)
    "stall_frames": 0,         # frames where nothing moves in the middle of a transition
    "flash_frames": 0,         # transient frames (placeholders, wrong chrome) that vanish again
    "main_busy_max_ms": 16.7,  # longest main-thread pass: one frame at the simulator's 60 Hz (aim for 8 on a 120 Hz phone)
    "dropped_frames": 0,       # display-link frames the app missed during the scenario
    "tap_commit_ms": 8,        # worst time from a tap to its animation reaching Core Animation
}

# Which targets each scenario is judged on (round trips only mean something when tapping fast).
CHECKS = {
    "deck-rapid": ["fall_ms", "tap_commit_ms", "stall_frames", "flash_frames", "main_busy_max_ms", "dropped_frames"],
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


# ---------------------------------------------------------------- build, serve, launch

def build(args):
    sim = udid()
    started = time.time()
    log = os.path.join(os.path.dirname(DERIVED), "build.log")
    os.makedirs(os.path.dirname(log), exist_ok=True)
    with open(log, "w") as out:
        code = subprocess.call(["xcodebuild", "-project", PROJECT, "-scheme", "Ardia", "-configuration", "Release",
                                "-destination", f"id={sim}", "-derivedDataPath", DERIVED,
                                "COMPILER_INDEX_STORE_ENABLE=NO", "-quiet", "build"], stdout=out, stderr=subprocess.STDOUT)
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


def launch(args, tabs=6, extra=()):
    sim = udid()
    serve_fixtures()
    sh(["xcrun", "simctl", "terminate", sim, BUNDLE], check=False)
    sh(["xcrun", "simctl", "launch", sim, BUNDLE, "-ArdiaDemo", "-ArdiaProbe", "-ArdiaRestingStart",
        "-ArdiaHarnessSeed", FIXTURES, "-ArdiaHarnessTabs", str(tabs), "-BrowseSurface", "browsing", *extra])
    deadline = time.time() + 20
    while time.time() < deadline:
        if any(e.get("name") == "seed.done" for e in read_probe(sim) if e.get("k") == "m"):
            break
        time.sleep(0.2)
    time.sleep(2.5)  # let the selected page load and paint
    return sim


# ---------------------------------------------------------------- UI helpers

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
    sh(["axe", "batch", "--udid", sim, *sum((["--step", s] for s in steps), [])], timeout=600)


# ---------------------------------------------------------------- scenarios

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


def scenario_swipe_tabs(sim, swipes=6):
    """Swipe sideways along the bottom bar to step between tabs."""
    tabs = find(sim, "Tabs")
    y = tabs["y"] if tabs else 820
    steps = []
    for i in range(swipes):
        a, b = (300, 100) if i % 2 == 0 else (100, 300)
        steps += [f"swipe --start-x {a} --start-y {y:.0f} --end-x {b} --end-y {y:.0f} --duration 0.12", "sleep 0.5"]
    steps.append("sleep 1.0")
    return steps


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
        # Alternate the page's own card (the return path) and the one to its left (the switch path).
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
    steps = []
    for _ in range(cycles):
        steps += [f"tap -x {x:.0f} -y {y:.0f}", "sleep 0.6", f"tap -x {x:.0f} -y {y:.0f}", "sleep 0.5",
                  f"tap -x {x:.0f} -y {y:.0f}", "sleep 0.5", f"tap -x {x:.0f} -y {y:.0f}", "sleep 0.5",
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


SCENARIOS = {
    "search-plus": scenario_search_plus,
    "deck-rapid": scenario_deck_rapid,
    "deck-pingpong": scenario_deck_pingpong,
    "deck-grid": scenario_deck_grid,
    "deck-interrupt": scenario_deck_interrupt,
    "deck-settled": scenario_deck_settled,
    "swipe-tabs": scenario_swipe_tabs,
    "deck-switch": scenario_deck_switch,
    "search-toggle": scenario_search_toggle,
}


# ---------------------------------------------------------------- analysis

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
                # a frozen run inside a trip; a long one is the switcher sitting open, not a stall
                frozen = pts[j] - pts[i]
                # ignore sub-two-frame gaps (recordings are variable-rate); a long freeze is the
                # switcher sitting open between taps, not a stall
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
    # each trip splits at its furthest point from the page: rise (leaving) and fall (coming home)
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
    """Media time at which the scripted interaction began (setup and calibration happen before it)."""
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

    # tap -> commit: how long after a tap its run-loop pass ends and the animation reaches Core Animation
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
    return {
        "display_fps": fps,
        "dropped_frames": dropped,
        "late_frames": late[:20],
        "main_busy_max_ms": round(passes[-1][0], 1) if passes else 0,
        "main_busy_over_16ms": sum(1 for p in passes if p[0] > 16),
        "worst_main_passes": worst,
        "latencies": latencies,
        "marks": [{"t": round(m["t"], 3), "name": m["name"], **({"detail": m["detail"]} if m.get("detail") else {})} for m in interaction][:80],
    }


def verdict(report):
    v = report.get("video", {})
    p = report.get("probe", {})
    checks = {
        "fall_ms": (v.get("fall_median_ms"), TARGETS["fall_ms"]),
        "stall_frames": (len(v.get("stalls", [])), TARGETS["stall_frames"]),
        "flash_frames": (len(v.get("flashes", [])), TARGETS["flash_frames"]),
        "main_busy_max_ms": (p.get("main_busy_max_ms"), TARGETS["main_busy_max_ms"]),
        "dropped_frames": (p.get("dropped_frames"), TARGETS["dropped_frames"]),
        "tap_commit_ms": (max([v for k, vs in p.get("latencies", {}).items() if k.endswith("->commit_ms") for v in vs], default=None), TARGETS["tap_commit_ms"]),
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
    """Main-thread CPU samples from trace.trace, grouped by the slow run-loop passes the probe saw."""
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
    # media time of the trace's zero
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
    report["verdict"] = verdict(report)
    report["trace"] = analyse_trace(directory, events, t0)
    json.dump(report, open(os.path.join(directory, "report.json"), "w"), indent=2)
    summarise(report)
    return report


def run(args):
    if args.scenario not in SCENARIOS:
        sys.exit(f"unknown scenario; choose from {', '.join(SCENARIOS)}")
    sim = launch(args, tabs=args.tabs)
    stamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
    directory = os.path.join(RUNS, f"{stamp}-{args.scenario}")
    os.makedirs(directory, exist_ok=True)
    steps = SCENARIOS[args.scenario](sim)
    video = os.path.join(directory, "video.mp4")
    recorder = subprocess.Popen(["xcrun", "simctl", "io", sim, "recordVideo", "--codec=h264", "--force", video],
                                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    tracer = None
    if args.trace:
        pid = sh(["xcrun", "simctl", "spawn", sim, "launchctl", "list"]).stdout
        pid = next((line.split()[0] for line in pid.splitlines() if BUNDLE in line and line.split()[0].isdigit()), None)
        if pid:
            tracer = subprocess.Popen(["xcrun", "xctrace", "record", "--template", "Time Profiler", "--device", sim,
                                       "--attach", pid, "--output", os.path.join(directory, "trace.trace")],
                                      stdout=open(os.path.join(directory, "trace.log"), "w"), stderr=subprocess.STDOUT)
            time.sleep(3.0)
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
    sub.add_parser("list").set_defaults(func=lambda a: [print(f"{k:14s} {v.__doc__}") for k, v in SCENARIOS.items()])
    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
