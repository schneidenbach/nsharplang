# Icon TODO

The `icon.svg` file contains the N# branding icon design.

For marketplace publishing, this needs to be converted to PNG format (128x128 pixels).

To convert:
```bash
# Using ImageMagick
convert -density 300 -background none icon.svg -resize 128x128 icon.png

# Or using Inkscape
inkscape icon.svg --export-type=png --export-filename=icon.png --export-width=128 --export-height=128

# Or use an online converter like cloudconvert.com
```

Then update package.json:
```json
"icon": "icon.png",
```
