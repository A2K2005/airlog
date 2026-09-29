Design sampling tools (Python 3, numpy, Pillow, fontTools). Run from this
folder; they read the design PNGs from ../../Widget.

  squircle.py   fits the tile corner (Figma corner smoothing) to the PNGs' alpha
  bgfit.py      fits each tile background as a base fill plus soft ellipses
                (bgcfg.json: masks per PNG) and writes bgfit_<name>.json
  gen_glow.py   writes lib/design/tokens/glow_recipes.dart from the fits
  measure.py    fits each text element's size, weight, tracking and baseline
                (textspec.json) against DM Sans and Subway Ticker Grid

bgfit.json holds the fits the shipped recipes were generated from.
