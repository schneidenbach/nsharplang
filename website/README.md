# N# Website

This is the landing page for the N# programming language.

## Local Development

To view the website locally, simply open `index.html` in your browser or use a simple HTTP server:

```bash
# Using Python
python3 -m http.server 8000

# Using Node.js
npx http-server
```

Then navigate to `http://localhost:8000`

## GitHub Pages Deployment

The website is automatically deployed to GitHub Pages via GitHub Actions when changes are pushed to the `website/` directory.

### Setup Instructions

1. Go to repository Settings > Pages
2. Under "Source", select "GitHub Actions"
3. The workflow in `.github/workflows/deploy-website.yml` will handle deployment

### Custom Domain (nsharp.dev)

To configure a custom domain:

1. Add a `CNAME` file to the `website/` directory with content: `nsharp.dev`
2. Configure DNS:
   - Add a CNAME record pointing to `<username>.github.io`
   - Or add A records pointing to GitHub Pages IPs
3. In GitHub repository settings, add the custom domain under Pages settings

## Features

- Mobile responsive design
- Fast load time (<1s)
- Professional gradient design
- Clean, semantic HTML5
- Optimized CSS with media queries
- SVG favicon for crisp display
