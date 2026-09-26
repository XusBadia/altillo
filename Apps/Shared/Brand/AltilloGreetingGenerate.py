#!/usr/bin/env python3
"""Regenerate SwiftUI cubic commands from the greeting SVG's three paths."""

import re
from pathlib import Path

root = Path(__file__).resolve().parents[3]
svg = (root / "Apps/Shared/Brand/AltilloGreeting.svg").read_text()
swift_path = root / "Apps/macOS/Onboarding/AltilloGreeting.swift"
swift = swift_path.read_text()
paths = re.findall(r'<path d="([^"]+)"', svg)
if len(paths) != 3:
    raise ValueError("Expected main lettering, t crossbar, and i dot")

lines = []
for index, data in enumerate(paths):
    tokens = re.findall(r"[MC]|-?\d+(?:\.\d+)?", data)
    if len(tokens) < 3 or tokens[0] != "M":
        raise ValueError(f"Path {index} must begin with M")
    lines.append(f"        case {index}:")
    lines.append(f"            path.move(to: CGPoint(x: {tokens[1]}, y: {tokens[2]}))")
    cursor = 3
    while cursor < len(tokens):
        if tokens[cursor] != "C" or cursor + 6 >= len(tokens):
            raise ValueError(f"Path {index} must contain only cubic curves")
        x1, y1, x2, y2, x3, y3 = tokens[cursor + 1 : cursor + 7]
        lines.extend(
            [
                f"            path.addCurve(to: CGPoint(x: {x3}, y: {y3}),",
                f"                          control1: CGPoint(x: {x1}, y: {y1}),",
                f"                          control2: CGPoint(x: {x2}, y: {y2}))",
            ]
        )
        cursor += 7

start = "        // BEGIN GENERATED SVG PATHS\n"
end = "        // END GENERATED SVG PATHS"
head, rest = swift.split(start, 1)
_, tail = rest.split(end, 1)
swift_path.write_text(head + start + "\n".join(lines) + "\n" + end + tail)
