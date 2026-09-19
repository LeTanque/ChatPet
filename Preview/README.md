# Blue Turtle preview

Bundled pet with thicker outlines — same frames as the app.

```sh
python3 Scripts/build-blue-turtle-preview.py
open Preview/blue-turtle/preview.html
```

# Leonardo preview (not bundled yet)

Use the **full PNG** in `Scripts/sources/leonardo-sheet.png` (2039×9540), not the tiny JPEG Cursor attaches in chat.

1. Regenerate frames:

   ```sh
   python3 Scripts/build-leonardo-preview.py
   ```

2. Open the animation preview in a browser:

   ```sh
   open Preview/leonardo/preview.html
   ```

Clips: **idle** (5-frame sway at top of sheet), **move left/right**, **failed** (2 shocked frames), **downloading** (10-frame arms-out nunchuck spin from the hi-res PNG).

After you approve the preview, we bundle into `Sources/DesktopPet/Assets/`, build the app, and commit.
