#!/usr/bin/env fontforge -script
# Build MSBM10.otf for the MaTeXComparisonShowcase note.
#
# MaTeX renders \mathbb with the AMS `msbm` font; no OpenType math font
# reproduces that blackboard design, so the showcase's parser column couldn't
# match gold's double-struck letters.  This converts the msbm10 Type1 font
# (shipped with TeX Live, but Type1/.pfb which modern macOS won't load, and
# TeX-encoded with the blackboard letters at ASCII slots A-Z) into an OpenType
# font whose blackboard letters sit at their proper Unicode double-struck
# codepoints - so the front end can render `ℝ`, `ℂ`, ... in the real msbm.
#
# Run:  fontforge -script dev/make-msbm-otf.py
# then the showcase auto-detects ~/Library/Fonts/MSBM10.otf (see applyMathFont
# / $msbmFont).  Requires: fontforge (brew install fontforge) + TeX Live.

import fontforge, os, subprocess

# locate msbm10.pfb via kpsewhich, with a TeX Live fallback
try:
    src = subprocess.check_output(["kpsewhich", "msbm10.pfb"]).decode().strip()
except Exception:
    src = "/usr/local/texlive/2023/texmf-dist/fonts/type1/public/amsfonts/symbols/msbm10.pfb"
assert os.path.exists(src), "msbm10.pfb not found (install TeX Live / amsfonts)"

out = os.path.expanduser("~/Library/Fonts/MSBM10.otf")

# msbm10 holds blackboard A-Z at ASCII slots 65-90; remap each to its Unicode
# double-struck codepoint (the seven Letterlike holes + the math-alphanumeric block)
caps = [0x1D538, 0x1D539, 0x2102, 0x1D53B, 0x1D53C, 0x1D53D, 0x1D53E, 0x210D, 0x1D540,
        0x1D541, 0x1D542, 0x1D543, 0x1D544, 0x2115, 0x1D546, 0x2119, 0x211A, 0x211D,
        0x1D54A, 0x1D54B, 0x1D54C, 0x1D54D, 0x1D54E, 0x1D54F, 0x1D550, 0x2124]

f = fontforge.open(src)
for i, cp in enumerate(caps):
    try:
        f[65 + i].unicode = cp
    except Exception as e:
        print("skip slot", 65 + i, e)
f.familyname = f.fontname = f.fullname = "MSBM10"
f.generate(out)
print("generated", out)
