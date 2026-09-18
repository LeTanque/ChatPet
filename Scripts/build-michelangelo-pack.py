#!/usr/bin/env python3
"""Slice Michelangelo frames from the bundled TMNT sprite sheet into a Blue Turtle-style pack."""
from __future__ import annotations

import hashlib
import json
import sys
from collections import deque
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SHEET = ROOT / "Scripts/sources/michelangelo-sheet.png"
PACK = ROOT / "Sources/DesktopPet/Assets/Michelangelo"
CANVAS = (192, 208)
# Match bundled Blue Turtle frame registration (see Assets/BlueTurtle/frames).
TARGET_CONTENT_HEIGHT = 169
MAX_CONTENT_WIDTH = 168
FOOT_PADDING = 9

# Selected bboxes (left, top, right, bottom) from the source sheet.
WALK_CYCLE: list[tuple[int, int, int, int]] = [
    (34, 121, 52, 156),
    (64, 120, 84, 156),
    (94, 122, 116, 155),
    (119, 123, 159, 155),
    (161, 126, 188, 155),
    (192, 128, 216, 157),
    (226, 133, 246, 156),
    (244, 121, 267, 155),
]

CLIPS: dict[str, list[tuple[int, int, int, int]]] = {
    # Side-view walk in place (skip the long stride frame so height stays consistent).
    "idle": [
        WALK_CYCLE[0],
        WALK_CYCLE[1],
        WALK_CYCLE[2],
        WALK_CYCLE[4],
        WALK_CYCLE[5],
        WALK_CYCLE[6],
    ],
    "runRight": WALK_CYCLE,
    "failed": [
        (0, 731, 28, 764),
        (238, 728, 268, 762),
        (244, 766, 262, 812),
        (265, 781, 283, 812),
        (4, 928, 29, 959),
        (30, 928, 56, 959),
        (73, 926, 94, 959),
        (105, 925, 128, 957),
    ],
    "laptop": [
        (43, 549, 75, 575),
        (76, 549, 107, 575),
        (127, 547, 158, 575),
        (275, 548, 302, 575),
        (394, 579, 418, 615),
        (421, 579, 445, 616),
    ],
}

FOLDERS = {
    "idle": "frames/idle",
    "runRight": "frames/running-right",
    "runLeft": "frames/running-left",
    "failed": "frames/failed",
    "laptop": "frames/running",
}


def flood_remove_sheet_black(image: Image.Image, tolerance: int = 8) -> Image.Image:
    """Remove sheet backdrop while keeping sprite outline pixels."""
    result = image.copy()
    pixels = result.load()
    width, height = result.size

    def is_backdrop(red: int, green: int, blue: int, alpha: int) -> bool:
        return alpha > 0 and red <= tolerance and green <= tolerance and blue <= tolerance

    seen = [[False] * width for _ in range(height)]
    queue: deque[tuple[int, int]] = deque()
    for x in range(width):
        for y in (0, height - 1):
            if is_backdrop(*pixels[x, y]):
                queue.append((x, y))
                seen[y][x] = True
    for y in range(height):
        for x in (0, width - 1):
            if is_backdrop(*pixels[x, y]) and not seen[y][x]:
                queue.append((x, y))
                seen[y][x] = True

    while queue:
        x, y = queue.popleft()
        pixels[x, y] = (0, 0, 0, 0)
        for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
            if 0 <= nx < width and 0 <= ny < height and not seen[ny][nx] and is_backdrop(*pixels[nx, ny]):
                seen[ny][nx] = True
                queue.append((nx, ny))
    return result


def tight_bbox(image: Image.Image) -> tuple[int, int, int, int]:
    pixels = image.load()
    width, height = image.size
    min_x, min_y, max_x, max_y = width, height, 0, 0
    found = False
    for y in range(height):
        for x in range(width):
            if pixels[x, y][3] > 10:
                found = True
                min_x = min(min_x, x)
                max_x = max(max_x, x)
                min_y = min(min_y, y)
                max_y = max(max_y, y)
    if not found:
        return (0, 0, width, height)
    return (min_x, min_y, max_x + 1, max_y + 1)


def prepare_crop(sheet: Image.Image, box: tuple[int, int, int, int], flip: bool) -> Image.Image:
    crop = flood_remove_sheet_black(sheet.crop(box))
    if flip:
        crop = crop.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
    return crop.crop(tight_bbox(crop))


def frame_scale(crop: Image.Image) -> float:
    native_width, native_height = crop.size
    scale = TARGET_CONTENT_HEIGHT / native_height
    if native_width * scale > MAX_CONTENT_WIDTH:
        scale = MAX_CONTENT_WIDTH / native_width
    return scale


def compose_frame(crop: Image.Image) -> Image.Image:
    scale = frame_scale(crop)
    native_width, native_height = crop.size
    scaled_width = max(1, int(round(native_width * scale)))
    scaled_height = max(1, int(round(native_height * scale)))
    crop = crop.resize((scaled_width, scaled_height), Image.Resampling.NEAREST)

    canvas = Image.new("RGBA", CANVAS, (0, 0, 0, 0))
    offset_x = (CANVAS[0] - scaled_width) // 2
    offset_y = CANVAS[1] - scaled_height - FOOT_PADDING
    canvas.paste(crop, (offset_x, offset_y), crop)
    return canvas


def main() -> int:
    sheet_path = SHEET
    if len(sys.argv) > 1:
        sheet_path = Path(sys.argv[1])
    if not sheet_path.is_file():
        print(f"Missing sprite sheet: {sheet_path}", file=sys.stderr)
        return 1

    img = Image.open(sheet_path).convert("RGBA")
    frame_hashes: dict[str, str] = {}

    for clip, boxes in CLIPS.items():
        folder = PACK / FOLDERS[clip]
        folder.mkdir(parents=True, exist_ok=True)
        crops = [prepare_crop(img, box, flip=False) for box in boxes]
        for index, crop in enumerate(crops):
            frame = compose_frame(crop)
            rel = f"{FOLDERS[clip]}/{index:02d}.png"
            out = PACK / rel
            frame.save(out)
            frame_hashes[rel] = hashlib.sha256(out.read_bytes()).hexdigest()

    run_boxes = CLIPS["runRight"]
    folder = PACK / FOLDERS["runLeft"]
    folder.mkdir(parents=True, exist_ok=True)
    for index, box in enumerate(run_boxes):
        crop = prepare_crop(img, box, flip=True)
        frame = compose_frame(crop)
        rel = f"{FOLDERS['runLeft']}/{index:02d}.png"
        out = PACK / rel
        frame.save(out)
        frame_hashes[rel] = hashlib.sha256(out.read_bytes()).hexdigest()

    sheet_hash = hashlib.sha256(sheet_path.read_bytes()).hexdigest()
    provenance = {
        "source": "User-provided TMNT-style sprite sheet; Michelangelo (orange mask) frames extracted for DesktopPet",
        "copyMethod": (
            "Edge flood-fill removes sheet black; sprites nearest-neighbor scaled to ~169px tall "
            "on a 192×208 transparent canvas (Blue Turtle registration)"
        ),
        "sourceSheetSHA256": sheet_hash,
        "frameSHA256": frame_hashes,
    }
    (PACK / "provenance.json").write_text(json.dumps(provenance, indent=2) + "\n")
    print(f"Wrote {len(frame_hashes)} frames to {PACK}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
