#!/usr/bin/env python3
"""Render current app scenarios in an isolated checkout, then format README assets.

Requires Xcode, XcodeGen and Pillow. Does not use promo's exported screenshots.
"""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import math
import os
from pathlib import Path
import subprocess
import tempfile

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
SCENARIOS = {
    "shelf": "openShelf", "ask": "openAssistant", "usage": "openUsage",
    "agents": "openAgents", "calendar": "openCalendar", "drawer": "openDrawer",
    "idle": "idleWithEars", "idle-agents": "idleWithAgentWaiting",
}


def run(*args, cwd=ROOT, **kwargs):
    return subprocess.run(args, cwd=cwd, check=True, **kwargs)


def banner(output):
    width, height = 1200, 760
    canvas = Image.new("RGB", (width, height))
    pixels = canvas.load()
    for y in range(height):
        for x in range(width):
            glow = math.exp(-(((x - 600) / 450) ** 2 + ((y - 230) / 220) ** 2))
            pixels[x, y] = (int(8 + 32 * glow), int(7 + 22 * glow), int(6 + 12 * glow))
    fonts = Path("/System/Library/Fonts/Supplemental")
    regular = lambda size: ImageFont.truetype(str(fonts / "Arial.ttf"), size)
    bold = lambda size: ImageFont.truetype(str(fonts / "Arial Bold.ttf"), size)
    draw = ImageDraw.Draw(canvas)
    icon = Image.open(ROOT / "website/public/altillo-icon.png").convert("RGBA")
    icon.thumbnail((36, 36))
    canvas.paste(icon, (44, 29), icon)
    draw.text((94, 32), "altillo", font=bold(28), fill="#f5efe5")
    draw.text((1156, 40), "Native macOS · Open source", font=regular(19),
              fill="#b8aa96", anchor="ra")
    shelf = Image.open(output / "shelf.png").convert("RGBA")
    shelf.thumbnail((1000, 330), Image.Resampling.LANCZOS)
    canvas.paste(shelf, ((width - shelf.width) // 2, 108), shelf)
    draw.text((600, 465), "Your notch, put to work.", font=bold(64),
              fill="#f5efe5", anchor="mt")
    draw.text((600, 566), "Files, your next meeting, what’s playing and your AI limits.",
              font=regular(25), fill="#b8aa96", anchor="mt")
    draw.text((600, 615), "One hover away, in the space your Mac already had.",
              font=regular(23), fill="#b8aa96", anchor="mt")
    draw.rounded_rectangle((530, 695, 670, 699), radius=2, fill="#c28b42")
    canvas.save(output / "banner.png", optimize=True)


def format_assets(raw, output, commit):
    output.mkdir(parents=True, exist_ok=True)
    for name, scenario in SCENARIOS.items():
        screenshot = Image.open(raw / f"{scenario}.png").convert("RGBA")
        box = screenshot.getchannel("A").point(lambda a: 255 if a > 40 else 0).getbbox()
        if box is None:
            raise ValueError(f"Empty screenshot: {scenario}")
        # Only crop transparent margins. Never upscale the app's native pixels.
        margin = max(8, round(screenshot.width / 780 * 8))
        box = (max(0, box[0] - margin), 0, min(screenshot.width, box[2] + margin),
               min(screenshot.height, box[3] + margin))
        screenshot.crop(box).save(output / f"{name}.png", optimize=True)
    banner(output)
    manifest = {
        "source_commit": commit,
        "captured_at": datetime.now(timezone.utc).isoformat(),
        "open_width_points": 700,
        "render_scale": 2,
        "content": "Design scenarios with sample data; native NSHostingView rendering",
        "assets": {f"{name}.png": {"scenario": scenario,
            "sha256": hashlib.sha256((output / f"{name}.png").read_bytes()).hexdigest()}
            for name, scenario in SCENARIOS.items()},
    }
    (output / "capture.json").write_text(json.dumps(manifest, indent=2) + "\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--format-only", type=Path, help="Use freshly rendered raw scenarios")
    parser.add_argument("--output", type=Path, default=ROOT / "docs/assets/readme")
    parser.add_argument("--derived-data", default="/tmp/altillo-dd-readme")
    args = parser.parse_args()
    commit = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
    if args.format_only:
        format_assets(args.format_only.resolve(), args.output.resolve(), commit)
        return
    env = os.environ.copy()
    env.setdefault("DEVELOPER_DIR", "/Applications/Xcode.app/Contents/Developer")
    with tempfile.TemporaryDirectory(prefix="altillo-readme-") as temp:
        temp = Path(temp)
        checkout, raw = temp / "checkout", temp / "raw"
        run("git", "worktree", "add", "--detach", str(checkout), commit)
        try:
            fixture = (ROOT / "script/readme/ScenarioExportTests.swift").read_text()
            fixture = fixture.replace('"__README_EXPORT_DIRECTORY__"', json.dumps(str(raw)))
            (checkout / "Tests/AltilloMacTests/ScenarioExportTests.swift").write_text(fixture)
            run("xcodegen", "generate", cwd=checkout, env=env)
            run("xcodebuild", "test", "-project", "Altillo.xcodeproj", "-scheme", "Altillo",
                "-destination", "platform=macOS", "-derivedDataPath", args.derived_data,
                "-only-testing:AltilloMacTests/ScenarioExportTests", "-testLanguage", "en",
                "-testRegion", "US", cwd=checkout, env=env)
            format_assets(raw, args.output.resolve(), commit)
        finally:
            run("git", "worktree", "remove", "--force", str(checkout))


if __name__ == "__main__":
    main()
