#!/usr/bin/env python3
"""Validate and package the prepared launch assets without publishing anything."""

import argparse
import hashlib
import json
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import zipfile


ROOT = Path(__file__).resolve().parent.parent
DEFAULT_OUTPUT = ROOT / "dist/Altillo-launch-2026-10-19.zip"

ASSETS = [
    "promo/producthunt/README.md",
    "promo/producthunt/thumbnail.png",
    "promo/producthunt/thumbnail-600.png",
    "promo/producthunt/thumbnail.gif",
    "promo/producthunt/altillo-producthunt.mp4",
    *[f"promo/producthunt/gallery/{name}.png" for name in (
        "01-hero", "02-drop-into-the-notch", "03-drag-it-out", "04-ai-usage",
        "05-ask", "06-agents", "07-everything", "08-free-open-source",
    )],
    "promo/youtube/README.md",
    "promo/youtube/ytavatar.png",
    "promo/youtube/ytbanner.png",
    "promo/youtube/ytthumb.png",
    "promo/videos/altillo-anuncio.mp4",
    "promo/videos/altillo-anuncio-en.mp4",
]
OPTIONAL_ASSETS = [
    "promo/videos/altillo-teaser.mp4",
    "promo/videos/altillo-teaser-en.mp4",
]
REFERENCES = [
    "README.md", "brand-context.md", "docs/cajon.md",
    "docs/release.md", "docs/desinstalacion-segura.md",
    "docs/launch-qa-2026-09-26.md", "docs/launch-qa-2026-10-03.md",
    "docs/releases/0.10.0.md",
    "plans/002-prove-release-differentiators.md",
    "plans/009-close-physical-launch-matrix.md",
]
IMAGE_SIZES = {
    **{path: (1270, 760) for path in ASSETS if "/gallery/" in path},
    "promo/producthunt/thumbnail.png": (240, 240),
    "promo/producthunt/thumbnail-600.png": (600, 600),
    "promo/producthunt/thumbnail.gif": (240, 240),
    "promo/youtube/ytavatar.png": (800, 800),
    "promo/youtube/ytbanner.png": (2560, 1440),
    "promo/youtube/ytthumb.png": (1280, 720),
}


def git(*args):
    return subprocess.check_output(["git", "-C", str(ROOT), *args], text=True).strip()


def inspect(path):
    relative = path.relative_to(ROOT).as_posix()
    if not path.is_file() or path.stat().st_size == 0:
        raise ValueError(f"Missing or empty launch file: {relative}")
    entry = {"path": relative, "bytes": path.stat().st_size}
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    entry["sha256"] = digest.hexdigest()
    entry["has_local_changes"] = bool(git("status", "--porcelain", "--", relative))
    if relative in IMAGE_SIZES:
        header = path.read_bytes()[:24]
        if header[:8] == b"\x89PNG\r\n\x1a\n":
            size = struct.unpack(">II", header[16:24])
        elif header[:6] in (b"GIF87a", b"GIF89a"):
            size = struct.unpack("<HH", header[6:10])
        else:
            raise ValueError(f"Invalid image: {relative}")
        if size != IMAGE_SIZES[relative]:
            raise ValueError(f"Wrong image dimensions: {relative}: {size}")
        entry["width"], entry["height"] = size
    if relative.endswith("thumbnail.gif") and entry["bytes"] >= 3_000_000:
        raise ValueError("Product Hunt thumbnail GIF must be smaller than 3 MB")
    return entry


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="Validate files without writing a ZIP")
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    args = parser.parse_args()
    launch = ROOT / "promo/launch"
    documents = sorted(path for path in launch.rglob("*") if path.suffix in (".md", ".csv", ".ics", ".json"))
    if not (launch / "README.md").is_file() or not any(path.suffix == ".ics" for path in documents):
        raise ValueError("Launch instructions and importable calendar are required in promo/launch/")
    files = [ROOT / name for name in ASSETS + REFERENCES] + documents
    files += [ROOT / name for name in OPTIONAL_ASSETS if (ROOT / name).is_file()]
    files = sorted(set(files))
    manifest = {
        "product": "Altillo",
        "launch_week": "2026-10-19/2026-10-25",
        "timezone": "Europe/Madrid",
        "source_commit": git("rev-parse", "HEAD"),
        "status": "Prepared assets and drafts; platform submissions are not performed by this tool.",
        "files": [inspect(path) for path in files],
    }
    print(f"Validated {len(files)} files ({sum(item['bytes'] for item in manifest['files']) / 1_000_000:.1f} MB)")
    if args.check:
        return
    output = args.output.expanduser().resolve()
    if output.suffix.lower() != ".zip" or not output.is_relative_to(ROOT / "dist"):
        raise ValueError("Output must be a .zip inside this repository's ignored dist/ directory")
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(dir=output.parent, suffix=".zip", delete=False) as temp:
        temp_path = Path(temp.name)
    try:
        with zipfile.ZipFile(temp_path, "w", compression=zipfile.ZIP_DEFLATED) as archive:
            for path in files:
                archive.write(path, path.relative_to(ROOT).as_posix())
            archive.writestr("manifest.json", json.dumps(manifest, indent=2, ensure_ascii=False) + "\n")
            archive.writestr("START-HERE.md", "# Altillo · 19–25 October 2026\n\nStart with [the launch instructions](promo/launch/README.md).\n\nThe calendar is a local reminder, not a scheduled platform launch. All copy is prepared for review; this ZIP does not register, publish or send anything.\n\nThe file manifest records SHA-256 hashes, image dimensions and any local changes included at packaging time.\n")
        temp_path.replace(output)
    finally:
        temp_path.unlink(missing_ok=True)
    with zipfile.ZipFile(output) as archive:
        bad = archive.testzip()
        if bad:
            raise ValueError(f"Corrupt ZIP member: {bad}")
    print(output)


if __name__ == "__main__":
    try:
        main()
    except (ValueError, subprocess.CalledProcessError) as error:
        print(error, file=sys.stderr)
        sys.exit(1)
