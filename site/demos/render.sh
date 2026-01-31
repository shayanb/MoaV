#!/bin/bash
# =============================================================================
# Terminal Demo Renderer
# Converts terminalizer YAML files to WebM videos for the website
#
# Usage:
#   ./render.sh                    # Render all YAML files
#   ./render.sh install.yml        # Render specific file
#   ./render.sh --clean            # Remove generated files
#
# Requirements:
#   - terminalizer (npm install -g terminalizer)
#   - ffmpeg (brew install ffmpeg / apt install ffmpeg)
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info() { echo -e "${CYAN}[INFO]${NC} $*"; }
success() { echo -e "${GREEN}[OK]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; }

# Check dependencies
check_deps() {
    local missing=()

    if ! command -v terminalizer &>/dev/null; then
        missing+=("terminalizer (npm install -g terminalizer)")
    fi

    if ! command -v ffmpeg &>/dev/null; then
        missing+=("ffmpeg (brew install ffmpeg / apt install ffmpeg)")
    fi

    if [[ ${#missing[@]} -gt 0 ]]; then
        error "Missing dependencies:"
        for dep in "${missing[@]}"; do
            echo "  - $dep"
        done
        exit 1
    fi
}

# Render a single YAML file to WebM
render_file() {
    local yaml_file="$1"
    local base_name="${yaml_file%.yml}"
    local gif_file="${base_name}.gif"
    local webm_file="${base_name}.webm"

    if [[ ! -f "$yaml_file" ]]; then
        error "File not found: $yaml_file"
        return 1
    fi

    info "Rendering $yaml_file..."

    # Step 1: Generate GIF with terminalizer
    info "  Generating GIF..."
    if ! terminalizer render "$yaml_file" -o "$gif_file"; then
        error "  terminalizer failed"
        return 1
    fi

    # Check if GIF was created (terminalizer might output to different location)
    if [[ ! -f "$gif_file" ]]; then
        # Try to find the generated GIF (terminalizer sometimes ignores -o)
        local found_gif=$(ls -t render*.gif 2>/dev/null | head -1)
        if [[ -n "$found_gif" ]]; then
            warn "  terminalizer created $found_gif instead of $gif_file, renaming..."
            mv "$found_gif" "$gif_file"
        else
            error "  GIF not found. Check terminalizer output."
            return 1
        fi
    fi

    local gif_size=$(du -h "$gif_file" | cut -f1)
    success "  GIF created ($gif_size)"

    # Step 2: Convert GIF to WebM
    info "  Converting to WebM (this may take a moment)..."
    if ! ffmpeg -y -i "$gif_file" \
        -c:v libvpx-vp9 \
        -b:v 0 -crf 32 \
        -pix_fmt yuv420p \
        -an \
        -loglevel warning \
        "$webm_file"; then
        error "  ffmpeg conversion failed"
        return 1
    fi

    if [[ ! -f "$webm_file" ]]; then
        error "  WebM file not created"
        return 1
    fi

    # Step 3: Clean up GIF
    rm -f "$gif_file"

    local size=$(du -h "$webm_file" | cut -f1)
    success "  Created $webm_file ($size)"
}

# Render all YAML files
render_all() {
    local count=0
    local yaml_files=(*.yml)

    if [[ ${#yaml_files[@]} -eq 0 ]] || [[ ! -f "${yaml_files[0]}" ]]; then
        warn "No YAML files found in $SCRIPT_DIR"
        echo ""
        echo "To create a new demo:"
        echo "  1. terminalizer record demo-name.yml"
        echo "  2. Edit demo-name.yml to adjust timing/content"
        echo "  3. ./render.sh demo-name.yml"
        return 0
    fi

    for yaml_file in *.yml; do
        [[ -f "$yaml_file" ]] || continue
        render_file "$yaml_file"
        ((count++)) || true
    done

    echo ""
    success "Rendered $count demo(s)"
}

# Clean generated files
clean() {
    info "Cleaning generated files..."
    rm -f *.webm *.gif
    success "Cleaned"
}

# Show help
show_help() {
    cat << 'EOF'
Terminal Demo Renderer

Usage:
  ./render.sh                    Render all YAML files to WebM
  ./render.sh <file.yml>         Render a specific YAML file
  ./render.sh --clean            Remove generated WebM/GIF files
  ./render.sh --help             Show this help

Creating a new demo:
  1. Record:    terminalizer record my-demo.yml
  2. Edit:      nano my-demo.yml  (adjust timing, remove mistakes)
  3. Render:    ./render.sh my-demo.yml

Demo files for MoaV website:
  - install.yml         Quick installation demo
  - bootstrap.yml       Bootstrap & setup demo
  - services.yml        Running services and status demo
  - users.yml           User management and packaging demo

Tips:
  - Keep demos short (30-60 seconds max)
  - Use clear, readable commands
  - Add delays for important steps (frameDelay in YAML)
  - Test the WebM plays correctly before committing
EOF
}

# Main
main() {
    case "${1:-}" in
        --help|-h)
            show_help
            ;;
        --clean)
            clean
            ;;
        "")
            check_deps
            render_all
            ;;
        *)
            check_deps
            render_file "$1"
            ;;
    esac
}

main "$@"
