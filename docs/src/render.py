#!/usr/bin/env python3
"""Renders docs/src/infographics.html to the PNGs in docs/ with headless Chrome (2x).

    python3 docs/src/render.py [--chrome PATH]

Heights are the sheets' measured heights at 1600 px wide; update them if the content changes.
"""
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
DOCS = os.path.dirname(HERE)
SHEETS = {"how": ("how-it-works.png", 980), "line": ("the-line.png", 1013),
          "privacy": ("privacy.png", 839), "problem": ("problem.png", 971), "live": ("live-gap.png", 1222)}
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"


def main(argv):
    chrome = argv[argv.index("--chrome") + 1] if "--chrome" in argv else CHROME
    page = "file://" + os.path.join(HERE, "infographics.html")
    for sheet, (name, height) in SHEETS.items():
        out = os.path.join(DOCS, name)
        subprocess.run([chrome, "--headless=new", "--use-mock-keychain", "--password-store=basic", "--disable-gpu", "--hide-scrollbars",
                        "--force-device-scale-factor=2", "--window-size=1600,%d" % height,
                        "--virtual-time-budget=6000", "--screenshot=" + out, page + "?show=" + sheet],
                       check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        print("wrote", os.path.relpath(out, os.path.dirname(DOCS)))


if __name__ == "__main__":
    main(sys.argv)
