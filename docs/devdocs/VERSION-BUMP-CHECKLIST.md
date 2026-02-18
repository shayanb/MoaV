# Version Bump Checklist

Step-by-step checklist for releasing a new MoaV version. Use this every time you bump the version.

---

## 1. Pre-release: Collect Changes

- [ ] Review `git log` since last release tag
- [ ] Identify all Added / Changed / Fixed / Security items
- [ ] Note any breaking changes that require user action

---

## 2. Update Version References

All files that contain the version number:

### 2a. `VERSION` file (root)
```
1.X.Y
```
- Single line, no prefix, no trailing content
- This is the source of truth — `moav.sh` reads it at runtime via `cat VERSION`

### 2b. `README.md` — version badge
```markdown
[![Version](https://img.shields.io/badge/version-1.X.Y-blue.svg)](CHANGELOG.md)
```

### 2c. `site/index.html` — JSON-LD schema
```json
"softwareVersion": "1.X.Y",
```
- Located in the `<script type="application/ld+json">` block near the top

### 2d. `site/style.css` — (check for version in footer/comments if applicable)

### 2e. Files that do NOT need manual version updates
- `moav.sh` — reads from `VERSION` file at runtime, no hardcoded version
- `README-fa.md` — no version badge
- `site/demos/install.yml` — may contain version strings from other tools (e.g., runc), not MoaV

---

## 3. Update CHANGELOG.md

### 3a. Move `[Unreleased]` items into new version section
```markdown
## [Unreleased]

## [1.X.Y] - YYYY-MM-DD

### Added
- ...

### Changed
- ...

### Fixed
- ...
```

### 3b. Add link reference at bottom of file
```markdown
[Unreleased]: https://github.com/shayanb/MoaV/compare/v1.X.Y...HEAD
[1.X.Y]: https://github.com/shayanb/MoaV/compare/v1.X-1.Z...v1.X.Y
```
- Update the `[Unreleased]` link to compare from the NEW version
- Add a new link for the new version comparing from the PREVIOUS version

### 3c. Changelog style
- Follow [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) format
- Group by: Added, Changed, Fixed, Security, Breaking Changes
- Link GitHub issues where applicable: `([#48](https://github.com/shayanb/MoaV/issues/48))`
- Bold the feature name, then dash, then description

---

## 4. Component Version Updates (if applicable)

If any component versions were bumped in this release, verify they are consistent across:

| Component | `.env.example` | `docker-compose.yml` (build args) | `Dockerfile` (ARG default) |
|-----------|---------------|-----------------------------------|---------------------------|
| sing-box | `SINGBOX_VERSION` | client build args | `Dockerfile.client` |
| wstunnel | `WSTUNNEL_VERSION` | client build args | `Dockerfile.client` |
| snowflake | `SNOWFLAKE_VERSION` | client + snowflake build args | `Dockerfile.client` |
| TrustTunnel | `TRUSTTUNNEL_VERSION` | trusttunnel build args | `Dockerfile.trusttunnel` |
| TrustTunnel Client | `TRUSTTUNNEL_CLIENT_VERSION` | client build args | `Dockerfile.client` |
| awg-tools | `AWGTOOLS_VERSION` | amneziawg + client build args | `Dockerfile.amneziawg`, `Dockerfile.client` |
| Prometheus | `PROMETHEUS_VERSION` | — | `Dockerfile.prometheus` |
| Grafana | `GRAFANA_VERSION` | — | `Dockerfile.grafana` |
| Conduit | `CONDUIT_VERSION` | conduit build args | `Dockerfile.conduit` |

Pattern: `.env.example` is the source, `docker-compose.yml` passes as build arg with fallback default, `Dockerfile` has `ARG` with same fallback default.

---

## 5. Commit and Tag

```bash
# Stage all version-bumped files
git add VERSION README.md CHANGELOG.md site/index.html

# Commit
git commit -m "release: v1.X.Y"

# Tag (after merge to main)
git tag -a v1.X.Y -m "v1.X.Y"
git push origin v1.X.Y
```

---

## 6. Create GitHub Release

### 6a. PR description template

```markdown
## Release v1.X.Y

### Highlights
- [1-3 sentence summary of the most important changes]

### Full changelog
See [CHANGELOG.md](CHANGELOG.md#1XY---yyyy-mm-dd) for complete details.

### Upgrade notes
- [Any breaking changes or required user actions]
- [Or: "No breaking changes. Run `moav update` to upgrade."]
```

### 6b. GitHub Release body template

```markdown
## What's New

[Copy the Added/Changed/Fixed sections from CHANGELOG.md]

## Upgrade

```bash
moav update
```

[If breaking changes exist:]
> **Breaking:** [description]. After updating, run `moav config rebuild` to regenerate configs.

## Full Changelog
https://github.com/shayanb/MoaV/compare/v1.X-1.Z...v1.X.Y
```

### 6c. Release creation
```bash
gh release create v1.X.Y \
  --title "v1.X.Y" \
  --notes-file /tmp/release-notes.md
```

---

## 7. Post-release

- [ ] Verify `moav update` works (pulls new version, shows correct version in header)
- [ ] Update website if needed (`site/` changes)
- [ ] Announce on relevant channels if major release

---

## Quick Reference: Minimal Version Bump

For a minimal release, the absolute minimum files to touch:

1. `VERSION` — bump number
2. `CHANGELOG.md` — add entry + update links
3. `README.md` — update badge
4. `site/index.html` — update softwareVersion

That's 4 files. Everything else (`moav.sh`, docker images, etc.) picks up the version automatically.
