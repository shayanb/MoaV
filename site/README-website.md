# MoaV Landing Page

Documentation for the moav.sh landing page.

## Site Structure

```
site/
├── index.html      # Main landing page (EN)
├── style.css       # Styles (dark theme, animations)
├── script.js       # Particle animation, copy buttons, typing effect
├── install.sh      # One-liner installer script
├── CNAME           # Custom domain configuration
├── README-website.md
└── assets/
    ├── moav.sh.png    # Terminal screenshot
    ├── favicon.png    # Favicon (TODO)
    └── og-image.png   # Social share image (TODO)
```

## Deployment

### How It Works

The site is deployed automatically via GitHub Actions when changes are pushed to the `main` branch.

**Trigger conditions:**
- Any file in `site/` is modified on `main` branch
- Manual trigger via "Run workflow" button in GitHub Actions


### Local Development

```bash
# Serve locally for testing
cd site && python3 -m http.server 8000

# Open http://localhost:8000
```

## Assets TODO

- [ ] `assets/favicon.png` - Site favicon
- [ ] `assets/og-image.png` - Social share image (1200x630px recommended)
- [ ] Demo GIFs for the "See It In Action" section:
  - Installation process
  - Bootstrap wizard
  - Running services
  - User management

## Customization

### Colors (in style.css)

```css
:root {
    --bg-primary: #0a0a0f;      /* Main background */
    --accent-cyan: #00d4ff;      /* Primary accent */
    --accent-purple: #7b5cff;    /* Secondary accent */
    --accent-green: #00ff88;     /* Success/terminal prompt */
}
```