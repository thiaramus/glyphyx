# Glyphyx

A Metal-powered macOS screensaver that renders cascading characters across floating 3D panes arranged in concentric rings. The camera drifts through the rings as streams of text rain down on every surface.

## Requirements

- macOS 13.0 or later
- Xcode with Metal support (to build from source)

## Installing from a Release

Pre-built releases are available on the [Releases](../../releases) page. Because the build is unsigned, macOS will block it on first open. Here's how to get past that:

1. Download `Glyphyx.saver` from the latest release and double-click it to install. Choose to install for your user only or all users when prompted.
2. Open **System Settings → Screen Saver** and select **Glyphyx**. macOS will show a warning saying it cannot be opened and offer to delete it. **Do not delete it** — click **Cancel**.
3. Open **System Settings → Privacy & Security** and scroll down until you see a message about Glyphyx being blocked. Click **Open Anyway**.
4. Go back to **System Settings → Screen Saver**, select Glyphyx again, and confirm by clicking **Open** in the dialog that appears.

Glyphyx is now trusted and will run normally.

## Building & Installing

```bash
# Clone the repo
git clone https://github.com/thiaramus/glyphyx.git
cd glyphyx

# Build (unsigned — works for personal use)
./build.sh

# Build and sign with your Developer ID
./build.sh --sign
```

Double-click `build/Glyphyx.saver` to install. macOS will ask whether to install for the current user or all users.

After installing, open **System Settings → Screen Saver**, select **Glyphyx**, and click **Options…** to configure it.

> **Tip for testing:** After reinstalling a new build, run the following in Terminal to force macOS to reload the screensaver engine:
> ```bash
> killall ScreenSaverEngine; killall legacyScreenSaver
> ```

---

## Configuration

All settings are available through the **Options…** button in System Settings → Screen Saver.

### Font

| Setting | Default | Description |
|---------|---------|-------------|
| **Font** | Menlo | Font family used to render characters. Only monospace families are listed — proportional fonts would break the grid alignment. |
| **Font Size** | 14 pt | Size of each character in the atlas. Smaller sizes pack more columns into each pane; larger sizes are more readable from a distance. Range: 8–72 pt. |

The screensaver always prefers the **Bold** variant of the chosen family for maximum readability against dark backgrounds. If no bold variant exists, the first available member is used.

---

### Colors

| Setting | Default | Description |
|---------|---------|-------------|
| **Foreground Color** | White | Color of the character at the head of each falling stream (the brightest point). The trail behind it is automatically rendered at 55% of this color, giving a natural fade. |
| **Glow Color** | Soft blue (50% opacity) | A bloom added around the head character. The alpha channel of this color controls glow intensity — set alpha to 0 to disable glow entirely. |
| **Background Color** | Black | Fill color of the canvas. Works well with any dark color; bright backgrounds are not recommended. |

---

### Animation

| Setting | Default | Range | Description |
|---------|---------|-------|-------------|
| **Fall Speed** | 1.00× | 0.25×–4.00× | Multiplier applied to every column's fall rate. Each column already has a randomised base speed (4–12 characters/sec); this scales all of them together. `0.25×` is a slow meditative drift; `4.00×` is frantic. |
| **Animation Mode** | On (3D) | — | Toggles between **3D** (camera flying through rings of panes) and **2D** (a single full-screen character grid, like a classic terminal). |
| **Camera Speed** | 1.00× | 0.00×–3.00× | Only visible when 3D mode is enabled. Controls how fast the camera orbits through the pane rings. `0.00×` freezes the camera in place while characters still animate. |

**How 3D mode works:** 21 panes are arranged in three concentric rings (5 + 7 + 9 panes at radii 4, 7.5, and 11 units). The camera orbits inside the innermost ring, looking outward toward whichever panes are in front of it as it moves. Each pane runs its own independent character simulation.

---

### Content

| Setting | Default | Description |
|---------|---------|-------------|
| **Character Set** | ASCII letters, digits, punctuation | The pool of characters the screensaver randomly picks from. Up to 96 characters are used; any beyond that are ignored. You can use any Unicode characters your chosen font supports, including full-width and half-width katakana. |

---

## Preset ideas

### Retro terminal
Green foreground, black background, 3D mode on, fall speed ~1.2×:

```
ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789@#$%&*<>{}[]|/=+~ｦｧｨｩｪｫｬｭｮｯｰｱｲｳｴｵｶｷｸｹｺｻｼｽｾｿﾀﾁﾂﾃﾄﾅﾆﾇﾈﾉ
```

Pair with **Foreground Color** `#00FF41` (or any bright green), **Glow Color** dark green at ~40% opacity, **Background Color** pure black.

### Minimal ASCII
White foreground, dark navy background, 2D mode, fall speed 0.5×:

```
ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789
```

Clean and understated.

### Dense noise
High fall speed (3×+), small font (10 pt), full punctuation:

```
!@#$%^&*()[]{}<>?/\|=+-~`'".,;:
```

---

## License

See [LICENSE](LICENSE).
