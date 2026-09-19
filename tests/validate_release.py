"""Check release metadata, publishable payload and all-in-one archives."""
import argparse
import hashlib
import io
import json
from pathlib import Path
import re
import runpy
import zipfile

ROOT = Path(__file__).resolve().parents[1]

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--archive", type=Path)
    args = parser.parse_args()
    release = json.loads((ROOT / "release.json").read_text())
    companion = runpy.run_path(str(ROOT / "octoprint-manual-multicolor/octoprint_manual_multicolor_ps3/version.py"))
    manifest = json.loads((ROOT / "plugins/com.amade.manual-multicolor/manifest.json").read_text())
    assert companion["VERSION"] == release["octoprint_version"]
    assert companion["DISPLAY_VERSION"] == release["version"]
    assert companion["PRUSASLICER_TARGET"] == release["prusaslicer_target"]
    assert manifest["version"] == release["lua_version"]
    assert manifest["min_slicer_version"] == release["prusaslicer_target"]
    printing = (ROOT / "presets/print-manual multicolor 2.0.yaml").read_text()
    printer = (ROOT / "presets/printer-MK4S manual multicolor.yaml").read_text()
    assert "tool.nozzle_high_flow" in printing and "wipe_tower: false" in printing
    assert "binary_gcode: false" in printer and "MANUAL_COLOUR_TOOLCHANGE" in printer
    assert "MANUAL_COLOUR_BOTTOM_LAYERS=2" in printer and "M600" in printer
    for forbidden in ("M708 ", "T[initial_tool]", "load to the nozzle"):
        assert forbidden not in printer, forbidden
    for required in ("README.md", "LICENSE", "THIRD_PARTY_NOTICES.md",
                     "licenses/AGPL-3.0.txt", "docs/SETUP.md", "docs/RELEASING.md",
                     "docs/TESTING.md", "octoprint-manual-multicolor/LICENSE"):
        assert (ROOT / required).is_file(), required
    if args.archive:
        with zipfile.ZipFile(args.archive) as archive:
            files = {n: archive.read(n) for n in archive.namelist() if not n.endswith("/")}
        prefix = f"PS3-Manual-Multicolor-{release['version']}-All-in-One/"
        assert all(n.startswith(prefix) for n in files)
        payload = {n[len(prefix):]: data for n, data in files.items()}
        assert "README.md" in payload and "settings.json" in payload
        inner = f"octoprint/OctoPrint-manual_multicolor_ps3-{release['octoprint_version']}.zip"
        assert inner in payload
        checks = {}
        for line in payload["CHECKSUMS.sha256"].decode().splitlines():
            digest, name = line.split("  ", 1)
            checks[name] = digest
        assert set(checks) == set(payload) - {"CHECKSUMS.sha256"}
        for name, digest in checks.items():
            assert hashlib.sha256(payload[name]).hexdigest() == digest, name
        for name, data in payload.items():
            assert not re.search(r"(^|/)(\.git|__pycache__|[^/]+\.egg-info)(/|$)", name), name
            assert not name.endswith((".pyc", ".log", ".bak", ".3mf", ".stl")), name
            if name.endswith(".gcode"):
                assert name.startswith("tests/fixtures/"), name
            if not name.endswith(".zip"):
                assert not re.search(rb"(?i)[A-Z]:[\\/]Users[\\/][^\\/\s]+", data), name
        with zipfile.ZipFile(io.BytesIO(payload[inner])) as archive:
            names = archive.namelist()
            assert any(n.endswith("/setup.py") for n in names)
            assert any(n.endswith("/LICENSE") for n in names)
            assert any(n.endswith("/static/js/manual_multicolor_ps3.js") for n in names)
            assert any(n.endswith("/templates/manual_multicolor_ps3_tab.jinja2") for n in names)
            assert not any("__pycache__" in n or n.endswith(".pyc") for n in names)
            for name in names:
                if not name.endswith("/"):
                    assert not re.search(rb"(?i)[A-Z]:[\\/]Users[\\/][^\\/\s]+", archive.read(name)), name
        print(f"PASS: archive checksums, inner installer, source, licenses and privacy ({len(payload)} files)")
    print("PASS: versions, target, required documentation and HF/manual presets")

if __name__ == "__main__":
    main()
