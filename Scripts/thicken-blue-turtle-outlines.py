#!/usr/bin/env python3
"""Expand Blue Turtle black outlines outward into transparent areas (one pixel per pass)."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
PACK = ROOT / "Sources/DesktopPet/Assets/BlueTurtle"
PASSES = 2
NEIGHBORS = (
    (-1, 0),
    (1, 0),
    (0, -1),
    (0, 1),
    (-1, -1),
    (-1, 1),
    (1, -1),
    (1, 1),
)


def is_black(r: int, g: int, b: int, a: int) -> bool:
    return a > 0 and r == 0 and g == 0 and b == 0


def thicken_outlines(image: Image.Image, passes: int = PASSES) -> Image.Image:
    result = image.convert("RGBA")
    px = result.load()
    width, height = result.size
    for _ in range(passes):
        additions: list[tuple[int, int]] = []
        for y in range(height):
            for x in range(width):
                if px[x, y][3] != 0:
                    continue
                for dx, dy in NEIGHBORS:
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < width and 0 <= ny < height and is_black(*px[nx, ny]):
                        additions.append((x, y))
                        break
        for x, y in additions:
            px[x, y] = (0, 0, 0, 255)
    return result


def sha256_file(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    frame_dir = PACK / "frames"
    paths = sorted(frame_dir.rglob("*.png"))
    if not paths:
        raise SystemExit(f"No frames under {frame_dir}")

    for path in paths:
        image = Image.open(path)
        thickened = thicken_outlines(image)
        thickened.save(path)

    provenance_path = PACK / "provenance.json"
    provenance = json.loads(provenance_path.read_text())
    pass_word = "pass" if PASSES == 1 else "passes"
    provenance["copyMethod"] = (
        "PNG frames with 12-color palette; black outlines expanded one pixel outward per pass "
        f"({PASSES} {pass_word}) via Scripts/thicken-blue-turtle-outlines.py"
    )
    provenance["frameSHA256"] = {
        str(path.relative_to(PACK)): sha256_file(path) for path in paths
    }
    provenance_path.write_text(json.dumps(provenance, indent=2) + "\n")
    print(f"Updated {len(paths)} frames in {PACK}")


if __name__ == "__main__":
    main()
