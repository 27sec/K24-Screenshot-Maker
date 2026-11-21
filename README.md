# K24 Screenshot Maker

macOS video player for TV recordings (`.ts`) with batch thumbnail (contact) sheets.

## Requirements
- macOS 15+
- ffmpeg and mpv: `brew install ffmpeg mpv`
  (libmpv is loaded at runtime from Homebrew for playback; ffmpeg does frame capture and sheets)

## Build
```bash
./build_app.sh
./build_app.sh --install   # builds and moves the app to /Applications
```

## Usage
- **Open** / drag & drop `.ts` files or a folder into the window.
- Click a row to play. Space = play/pause, ←/→ = seek 10 s, double-click video = full screen.
- Playback uses libmpv, so `.ts` files (H.264, HEVC, MPEG-2, AC-3/MP2 audio) play immediately
  with no conversion. Interlaced recordings are deinterlaced automatically.
- **Capture** saves the current frame as PNG to the Save-to folder.
- Tick files (or **Select all**) → **Create thumbnails (N)** → choose layout
  3×3 / 3×4 / 4×4 / 4×5 / 5×5,
  capture mode, JPEG/PNG, width → **Generate**. Output: `<name>_sheet.jpg`.

Headless: `FramePlayer --sheet <video> <outdir> [3x4]`
