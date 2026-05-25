#!/usr/bin/env python3
"""Compatibility wrapper for the template quickstart replay test."""

from pathlib import Path
import runpy
import sys


TARGET = Path(__file__).resolve().parents[1] / "tests" / "scripts" / "replay-template-quickstarts.py"
sys.argv[0] = str(TARGET)
runpy.run_path(str(TARGET), run_name="__main__")
