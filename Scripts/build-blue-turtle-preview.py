#!/usr/bin/env python3
"""Sync bundled Blue Turtle frames into Preview/blue-turtle for local HTML review."""
from __future__ import annotations

import json
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PACK = ROOT / "Sources/DesktopPet/Assets/BlueTurtle"
OUT = ROOT / "Preview/blue-turtle"

CLIP_LABELS = {
    "idle": "Idle",
    "runLeft": "Run left",
    "runRight": "Run right",
    "failed": "Failed / tired",
    "laptop": "Viewing laptop",
}

CLIP_ORDER = ("idle", "runLeft", "runRight", "failed", "laptop")


def main() -> None:
    pet = json.loads((PACK / "pet.json").read_text())
    OUT.mkdir(parents=True, exist_ok=True)
    preview_frames = OUT / "frames"
    if preview_frames.exists():
        shutil.rmtree(preview_frames)
    shutil.copytree(PACK / "frames", preview_frames)

    clips: dict[str, dict] = {}
    for clip_id in CLIP_ORDER:
        clip = pet["clips"][clip_id]
        paths = list(clip["frames"])
        clips[clip_id] = {
            "label": CLIP_LABELS[clip_id],
            "paths": paths,
            "frameCount": len(paths),
            "framesPerSecond": clip["framesPerSecond"],
            "frameDurations": clip["frameDurations"],
        }

    manifest = {
        "name": pet["name"],
        "canvas": {"width": 192, "height": 208},
        "footPadding": 9,
        "clips": clips,
    }
    (OUT / "preview-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    embed = "window.__PREVIEW_MANIFEST__ = " + json.dumps(manifest) + ";\n"
    (OUT / "preview-data.js").write_text(embed)
    print(f"Preview data → {OUT}")
    print("Open Preview/blue-turtle/preview.html in a browser.")


if __name__ == "__main__":
    main()
