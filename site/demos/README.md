# Terminal Demos

This directory contains terminalizer YAML files and rendered WebM videos for the website's "See It In Action" section.

## Files

| File | Description |
|------|-------------|
| `install.yml` | Quick installation demo |
| `setup.yml` | Bootstrap & setup demo (domain config, docker build, services) |
| `services.yml` | Running services and status demo |
| `users.yml` | User management and packaging demo |

## Creating a Demo

### 1. Record

```bash
# Start recording (this creates a YAML config file)
terminalizer record install.yml

# Run your commands in the terminal
# Press Ctrl+D to stop recording
```

### 2. Edit

Open the YAML file and adjust:
- **frameDelay**: Add delays after important commands (in ms)
- **cols/rows**: Terminal dimensions (recommend 100x30)
- **Remove mistakes**: Delete or fix any typos
- **cursorStyle**: Set to `block` or `underline`

Example YAML header:
```yaml
config:
  cols: 100
  rows: 30
  frameDelay: auto
  maxIdleTime: 2000
  cursorStyle: block
  fontFamily: "JetBrains Mono, monospace"
  fontSize: 14
  lineHeight: 1.2
  theme:
    background: "#0a0a0f"
    foreground: "#ffffff"
```

### 3. Preview (optional)

```bash
terminalizer play install.yml
```

### 4. Render

```bash
# Render a single file
./render.sh install.yml

# Or render all YAML files
./render.sh
```

This generates `install.webm` in the same directory.

## Requirements

- **terminalizer**: `npm install -g terminalizer`
- **ffmpeg**: `brew install ffmpeg` (macOS) or `apt install ffmpeg` (Linux)

## Tips

1. **Keep demos short** - 30-60 seconds max
2. **Use clear commands** - Viewers should understand what's happening
3. **Add pauses** - Let important output be visible (`frameDelay` in YAML)
4. **Test playback** - Check the WebM plays correctly before committing
5. **Consistent terminal size** - Use 100x30 for all demos

## Workflow for Updates

When updating a demo:

```bash
cd site/demos

# Re-record
terminalizer record install.yml

# Edit the YAML if needed
nano install.yml

# Render
./render.sh install.yml

# Test locally (open index.html in browser)
```

## File Size Guidelines

- Target: Under 1.5MB per WebM for fast loading
- The render script automatically:
  - Scales video to 1280px width
  - Reduces frame rate to 30fps
  - Uses CRF 35 for good compression
- If still too large:
  - Reduce terminal dimensions in YAML
  - Shorten the demo
  - Trim repetitive frames (e.g., docker build logs)
