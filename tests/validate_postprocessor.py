#!/usr/bin/env python3
"""Run the bundled transformer on a minimal three-layer virtual-tool file."""

from __future__ import annotations

import shutil
import subprocess
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / "tests" / "fixtures" / "three_layer_virtual_tools.gcode"
TRANSFORMER = (
    ROOT
    / "plugins"
    / "com.amade.manual-multicolor"
    / "postprocess"
    / "FlattenManualColoursAboveFirstLayer.ps1"
)


def main() -> None:
    with tempfile.TemporaryDirectory(prefix="manual-multicolor-") as temp_dir:
        target = Path(temp_dir) / FIXTURE.name
        shutil.copy2(FIXTURE, target)
        completed = subprocess.run(
            [
                "powershell.exe",
                "-NoProfile",
                "-ExecutionPolicy",
                "Bypass",
                "-File",
                str(TRANSFORMER),
                str(target),
            ],
            check=True,
            capture_output=True,
            text=True,
        )
        output = target.read_text(encoding="utf-8-sig")

    assert "removed 2 middle change(s)" in completed.stdout
    assert output.count("MANUAL_COLOUR_LIMIT: load base colour") == 1
    assert output.count("M600 E0.8 C\"") == 5
    assert "\nT0\n" not in output
    assert "\nT1\n" not in output
    assert "\nT2\n" not in output
    print("Validated bundled post-processor: 5 retained/manual pauses, 2 middle changes removed")


if __name__ == "__main__":
    main()
