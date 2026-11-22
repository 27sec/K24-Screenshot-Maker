# K24 Screenshot Maker

macOS video player for TV recordings (`.ts`) with batch thumbnail (contact) sheets.

## Requirements
- macOS 15+
- ffmpeg and mpv: `brew install ffmpeg mpv`
  (libmpv is loaded at runtime from Homebrew for playback; ffmpeg does frame capture and sheets)

## Download
1. Install the requirements above: `brew install ffmpeg mpv`
2. Download the latest `K24-Screenshot-Maker-*-arm64.zip` from
   [Releases](https://github.com/27sec/K24-Screenshot-Maker/releases/latest) (Apple Silicon only).
3. Unzip it and move **K24 Screenshot Maker.app** to `/Applications`.
4. The app is ad-hoc signed, not notarized, so macOS blocks the first launch.
   Right-click the app → **Open**, or run:
   ```bash
   xattr -dr com.apple.quarantine "/Applications/K24 Screenshot Maker.app"
   ```

## Build from source
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

## License
MIT, see [LICENSE](LICENSE). The bundled mpv headers in `Sources/CMpv/include` are ISC licensed.
