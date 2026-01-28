#!/bin/bash
# =============================================================================
# MoaV Release Helper
# Usage: ./scripts/release.sh <version>
# Example: ./scripts/release.sh 0.2.0
# =============================================================================

set -euo pipefail

VERSION="${1:-}"

if [[ -z "$VERSION" ]]; then
    echo "Usage: $0 <version>"
    echo "Example: $0 0.2.0"
    echo ""
    echo "Current version: $(cat VERSION)"
    exit 1
fi

# Validate version format
if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9]+)?$ ]]; then
    echo "Error: Invalid version format. Use semantic versioning (e.g., 0.2.0 or 0.2.0-beta)"
    exit 1
fi

CURRENT_VERSION=$(cat VERSION)
echo "Releasing MoaV v${VERSION} (current: v${CURRENT_VERSION})"
echo ""

# Update VERSION file
echo "$VERSION" > VERSION
echo "Updated VERSION file"

# Check if changelog has entry for this version
if grep -q "## \[$VERSION\]" CHANGELOG.md; then
    echo "Changelog entry exists for v${VERSION}"
else
    echo ""
    echo "WARNING: No changelog entry found for v${VERSION}"
    echo "Please add an entry to CHANGELOG.md before creating the release."
    echo ""
    echo "Template:"
    echo "## [$VERSION] - $(date +%Y-%m-%d)"
    echo ""
    echo "### Added"
    echo "- New features..."
    echo ""
    echo "### Changed"
    echo "- Changes..."
    echo ""
    echo "### Fixed"
    echo "- Bug fixes..."
    echo ""
fi

echo ""
echo "Next steps:"
echo "  1. Update CHANGELOG.md with release notes"
echo "  2. Commit: git add VERSION CHANGELOG.md && git commit -m 'Release v${VERSION}'"
echo "  3. Tag: git tag v${VERSION}"
echo "  4. Push: git push origin main --tags"
echo ""
echo "The GitHub Action will automatically create a release when you push the tag."
