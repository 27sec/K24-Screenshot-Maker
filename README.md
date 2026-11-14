# K24 Screenshot Maker

macOS video player for TV recordings (`.ts`) with batch thumbnail (contact) sheets.

## Requirements
- macOS 15+
- ffmpeg: `brew install ffmpeg`

## Build
```bash
./build_app.sh
./build_app.sh --install   # builds and moves the app to /Applications
```

## Usage
- **Open** / drag & drop `.ts` files or a folder into the window.
- Click a row to play. Space = play/pause, ←/→ = seek 10 s, double-click video = full screen.
- `.ts` files are converted into a cached MP4 for playback (`~/Library/Caches/FramePlayer`).
  H.264 → fast remux (seconds); MPEG-2 → hardware re-encode (first open only).
  Clear it from the menu: Playback → Clear Playback Cache.
- **Capture** saves the current frame as PNG to the Save-to folder.
- Tick files (or **Select all**) → **Create thumbnails (N)** → choose layout
  3×3 / 3×4 / 4×4 / 4×5 / 5×5,
  capture mode, JPEG/PNG, width → **Generate**. Output: `<name>_sheet.jpg`.

Headless: `FramePlayer --sheet <video> <outdir> [3x4]`
