#!/usr/bin/env python3
"""Build Michelangelo preview frames from horizontal strip PNGs in pets/."""
from __future__ import annotations

import importlib.util
import json
import shutil
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SOURCES = ROOT / "pets"
OUT = ROOT / "Preview/michelangelo"
ASSETS = ROOT / "Sources/DesktopPet/Assets/Michelangelo"

_spec = importlib.util.spec_from_file_location(
    "leonardo_build", ROOT / "Scripts/build-leonardo-preview.py"
)
_leo = importlib.util.module_from_spec(_spec)
assert _spec.loader
_spec.loader.exec_module(_leo)

CANVAS = _leo.CANVAS
FOOT_PADDING = _leo.FOOT_PADDING
TARGET_CONTENT_HEIGHT = 158
MAX_CONTENT_WIDTH = _leo.MAX_CONTENT_WIDTH

# clip_id -> (source file, split mode, frame count or None for gap-detect)
CLIP_SOURCES: dict[str, tuple[str, str, int | None]] = {
    "idle": ("idle.png", "gap", None),
    "idleReady": ("idle2.png", "gap", None),
    "runRight": ("walkright.png", "gap", None),
    "shocked": ("shocked.png", "gap", None),
    "fallOver": ("fallOver.png", "gap", None),
    "whirlwind": ("whirlwind.png", "whirlwind", None),
    "uppercut": ("uppercut.png", "equal", 4),
    "burned": ("burned.png", "gap", None),
}

BLUR_CLIPS = frozenset({"idleReady", "whirlwind", "uppercut"})

# Keep small FX (breath puffs) attached; do not drop secondary blobs.
NO_ISOLATE_CLIPS = BLUR_CLIPS | frozenset({"burned"})

# Anchor feet center to canvas center so swaying limbs do not slide the body sideways.
FOOT_ANCHOR_CLIPS = frozenset({"idle", "idleReady", "burned", "runRight", "runLeft"})

COMPOSE_OPTS: dict[str, dict] = {
    "shocked": {"backdrop": "key", "pad_crop": False, "content_height": 132},
    "burned": {"content_height": 148},
    "fallOver": {"content_height": 152},
    "whirlwind": {"content_height": 150},
}

DEFAULT_FPS = 10


def sprite_pixel(r: int, g: int, b: int, a: int) -> bool:
    return r + g + b > 60


def split_gap_row(path: Path, min_width: int = 12) -> list[tuple[int, int, int, int]]:
    sheet = Image.open(path).convert("RGBA")
    width, height = sheet.size
    empty_cols: list[bool] = []
    for x in range(width):
        empty_cols.append(
            all(not sprite_pixel(*sheet.getpixel((x, y))) for y in range(height))
        )
    boxes: list[tuple[int, int, int, int]] = []
    in_frame = False
    start = 0
    for x, is_empty in enumerate(empty_cols):
        if not is_empty and not in_frame:
            start = x
            in_frame = True
        elif is_empty and in_frame:
            if x - start >= min_width:
                boxes.append(_tighten_box(sheet, start, 0, x, height))
            in_frame = False
    if in_frame and width - start >= min_width:
        boxes.append(_tighten_box(sheet, start, 0, width, height))
    return boxes


def _tighten_box(
    sheet: Image.Image, left: int, top: int, right: int, bottom: int
) -> tuple[int, int, int, int]:
    min_x, min_y, max_x, max_y = right, bottom, left, top
    for y in range(top, bottom):
        for x in range(left, right):
            if sprite_pixel(*sheet.getpixel((x, y))):
                min_x = min(min_x, x)
                max_x = max(max_x, x)
                min_y = min(min_y, y)
                max_y = max(max_y, y)
    if max_x < min_x:
        return (left, top, right, bottom)
    return (min_x, min_y, max_x + 1, max_y + 1)


def split_equal_row(path: Path, count: int) -> list[tuple[int, int, int, int]]:
    sheet = Image.open(path).convert("RGBA")
    x0, x1, y0, y1 = 0, sheet.size[0], 0, sheet.size[1]
    return _leo.equal_slice_boxes(sheet, x0, x1, y0, y1, count)


def split_whirlwind_row(path: Path) -> list[tuple[int, int, int, int]]:
    """Rotation row: only split on full-height empty columns (interior gaps are partial)."""
    sheet = Image.open(path).convert("RGBA")
    width, height = sheet.size

    def is_separator_column(x: int) -> bool:
        empty = sum(
            1 for y in range(height) if not sprite_pixel(*sheet.getpixel((x, y)))
        )
        return empty / height > 0.98

    sep = [is_separator_column(x) for x in range(width)]
    boxes: list[tuple[int, int, int, int]] = []
    in_frame = False
    start = 0
    for x, is_sep in enumerate(sep):
        if not is_sep and not in_frame:
            start = x
            in_frame = True
        elif is_sep and in_frame:
            if x - start >= 30:
                boxes.append(_tighten_box(sheet, start, 0, x, height))
            in_frame = False
    if in_frame and width - start >= 30:
        boxes.append(_tighten_box(sheet, start, 0, width, height))
    return boxes


def boxes_for_clip(clip_id: str) -> list[tuple[int, int, int, int]]:
    filename, mode, count = CLIP_SOURCES[clip_id]
    path = SOURCES / filename
    if not path.is_file():
        raise FileNotFoundError(path)
    if mode == "whirlwind":
        boxes = split_whirlwind_row(path)
    elif mode == "equal":
        assert count is not None
        boxes = split_equal_row(path, count)
    else:
        boxes = split_gap_row(path)
    if not boxes:
        raise ValueError(f"No frames detected for {clip_id} ({filename})")
    return boxes


def foot_center_x(image: Image.Image, foot_rows: int = 14) -> float:
    pixels = image.load()
    width, height = image.size
    y0 = max(0, height - foot_rows)
    min_x, max_x = width, 0
    found = False
    for y in range(y0, height):
        for x in range(width):
            if pixels[x, y][3] > 10:
                min_x = min(min_x, x)
                max_x = max(max_x, x)
                found = True
    if not found:
        return width / 2
    return (min_x + max_x) / 2


def compose_frame(
    sheet: Image.Image,
    box: tuple[int, int, int, int],
    flip: bool,
    *,
    isolate_largest: bool = True,
    backdrop: str = "flood",
    pad_crop: bool = True,
    content_height: int = TARGET_CONTENT_HEIGHT,
    anchor_feet: bool = False,
) -> Image.Image:
    crop_box = _leo.expand_box(box, sheet.size) if pad_crop else box
    crop = sheet.crop(crop_box)
    if backdrop == "key":
        crop = _leo.key_remove_backdrop(crop)
    else:
        crop = _leo.flood_remove_backdrop(crop)
    if isolate_largest:
        crop = _leo.largest_foreground_component(crop)
    if flip:
        crop = crop.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
    crop = crop.crop(_leo.tight_bbox(crop))
    native_width, native_height = crop.size
    if native_height <= 0 or native_width <= 0:
        return Image.new("RGBA", CANVAS, (0, 0, 0, 0))
    scale = content_height / native_height
    if native_height < 32:
        scale = min(scale, 6.0)
    if native_width * scale > MAX_CONTENT_WIDTH:
        scale = MAX_CONTENT_WIDTH / native_width
    scaled_width = max(1, int(round(native_width * scale)))
    scaled_height = max(1, int(round(native_height * scale)))
    crop = crop.resize((scaled_width, scaled_height), Image.Resampling.NEAREST)

    canvas = Image.new("RGBA", CANVAS, (0, 0, 0, 0))
    if anchor_feet:
        foot_x = foot_center_x(crop)
        offset_x = int(round(CANVAS[0] / 2 - foot_x))
    else:
        offset_x = (CANVAS[0] - scaled_width) // 2
    offset_y = CANVAS[1] - scaled_height - FOOT_PADDING
    canvas.paste(crop, (offset_x, offset_y), crop)
    return canvas


def default_durations(frame_count: int, hold_last: float = 0.2) -> list[float]:
    if frame_count <= 1:
        return [0.5]
    base = 0.1
    durations = [base] * frame_count
    durations[-1] = hold_last
    return durations


    return durations


def install_app_assets(manifest: dict) -> None:
    clips: dict[str, dict] = {}
    for clip_id, info in manifest["clips"].items():
        clips[clip_id] = {
            "frames": info["paths"],
            "framesPerSecond": info["framesPerSecond"],
            "frameDurations": info["frameDurations"],
        }
    pack = {
        "schemaVersion": 1,
        "id": "builtin.michelangelo",
        "name": "Michelangelo",
        "species": "robot",
        "bodyColor": "#5DBF4A",
        "accentColor": "#F7941D",
        "clips": clips,
    }
    ASSETS.mkdir(parents=True, exist_ok=True)
    frames_dir = ASSETS / "frames"
    if frames_dir.exists():
        shutil.rmtree(frames_dir)
    shutil.copytree(OUT / "frames", frames_dir)
    (ASSETS / "pet.json").write_text(json.dumps(pack, indent=2) + "\n")
    provenance = {
        "source": "TMNT arcade-style strips in pets/; normalized to 192×208 with foot anchoring",
        "copyMethod": "Scripts/build-michelangelo-preview.py",
        "previewManifest": "Preview/michelangelo/preview-manifest.json",
    }
    (ASSETS / "provenance.json").write_text(json.dumps(provenance, indent=2) + "\n")
    print(f"Installed app pack → {ASSETS}")


def main() -> int:
    install = "--install" in sys.argv
    if not SOURCES.is_dir():
        print(f"Missing pets folder: {SOURCES}", file=sys.stderr)
        return 1

    if OUT.joinpath("frames").exists():
        shutil.rmtree(OUT / "frames")
    sheet_cache: dict[str, Image.Image] = {}

    def load_sheet(filename: str) -> Image.Image:
        if filename not in sheet_cache:
            sheet_cache[filename] = Image.open(SOURCES / filename).convert("RGBA")
        return sheet_cache[filename]

    manifest: dict = {
        "name": "Michelangelo (preview)",
        "canvas": {"width": CANVAS[0], "height": CANVAS[1]},
        "contentHeight": TARGET_CONTENT_HEIGHT,
        "footPadding": FOOT_PADDING,
        "clips": {},
    }

    for clip_id in CLIP_SOURCES:
        filename, _, _ = CLIP_SOURCES[clip_id]
        sheet = load_sheet(filename)
        boxes = boxes_for_clip(clip_id)
        opts = {
            "isolate_largest": clip_id not in NO_ISOLATE_CLIPS,
            "backdrop": "flood",
            "pad_crop": True,
            "content_height": TARGET_CONTENT_HEIGHT,
            "anchor_feet": clip_id in FOOT_ANCHOR_CLIPS,
            **COMPOSE_OPTS.get(clip_id, {}),
        }
        folder = OUT / "frames" / clip_id
        folder.mkdir(parents=True, exist_ok=True)
        paths: list[str] = []
        for index, box in enumerate(boxes):
            frame = compose_frame(sheet, box, flip=False, **opts)
            rel = f"frames/{clip_id}/{index:02d}.png"
            frame.save(OUT / rel)
            paths.append(rel)
        manifest["clips"][clip_id] = {
            "source": filename,
            "frameCount": len(paths),
            "paths": paths,
            "framesPerSecond": DEFAULT_FPS,
            "frameDurations": default_durations(len(paths)),
        }

    run_boxes = boxes_for_clip("runRight")
    run_sheet = load_sheet("walkright.png")
    run_opts = {
        "isolate_largest": True,
        "backdrop": "flood",
        "pad_crop": True,
        "content_height": TARGET_CONTENT_HEIGHT,
        "anchor_feet": True,
    }
    folder = OUT / "frames/runLeft"
    folder.mkdir(parents=True, exist_ok=True)
    left_paths: list[str] = []
    for index, box in enumerate(run_boxes):
        frame = compose_frame(run_sheet, box, flip=True, **run_opts)
        rel = f"frames/runLeft/{index:02d}.png"
        frame.save(OUT / rel)
        left_paths.append(rel)
    manifest["clips"]["runLeft"] = {
        "source": "walkright.png (mirrored)",
        "frameCount": len(left_paths),
        "paths": left_paths,
        "framesPerSecond": DEFAULT_FPS,
        "frameDurations": default_durations(len(left_paths)),
    }

    (OUT / "preview-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    embed = "window.__PREVIEW_MANIFEST__ = " + json.dumps(manifest) + ";\n"
    (OUT / "preview-data.js").write_text(embed)
    print(f"Built {len(manifest['clips'])} clips → {OUT}")
    for clip_id, info in manifest["clips"].items():
        print(f"  {clip_id}: {info['frameCount']} frames")
    if install:
        install_app_assets(manifest)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
