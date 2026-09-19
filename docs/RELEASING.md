# Maintaining releases across PrusaSlicer 3 updates

This repository packages PS3 tools and an OctoPrint companion together. Updating
a target string does not establish compatibility.

## Versioning

Current: **3.11A.08**, target **3.0.0-alpha11**.

- Next alpha11 fix: **3.11A.09**, Python **3.11a9**, Lua **3.11.9**.
- First alpha12 release: **3.12A.01**, Python **3.12a1**, Lua **3.12.1**.
- Keep plugin IDs unchanged: com.amade.manual-multicolor and manual_multicolor_ps3.
- Define and document a new scheme before beta/stable or another PS3 minor line;
  do not imply alpha numbering is the PrusaSlicer semantic version.
- Never replace an already-published ZIP under the same tag. Publish a new
  revision and retain previous releases for rollback.

Update **release.json**, Lua **manifest.json**, companion **version.py**,
README/download names, setup references and both changelogs together.
The package validator checks machine-readable version consistency.

## Compatibility checklist

1. Install the new Prusa version separately; retain the working installation.
2. Inspect Lua API/manifest changes and vendor preset IDs/conditions.
3. Check new text-G-code markers, full config footer, virtual T commands,
   toolchange blocks, start/end code, relative E and absolute XYZ.
4. Verify hardware selection produces the expected nozzle diameter/HF flag.
5. Check wiped/primed material behaviour, no real MMU startup/load/unload
   commands, and correct temperatures for the initial/reordered filament.
6. Test representative one-, two-, three- and five-slot models, a non-slot-1
   base, coloured top layers, base-only top layers, unsupported modes, and
   cancellation. Do not claim cases are tested until they are.
7. Run the regression suite in docs/TESTING.md, including all 36 two-row
   permutations and optional real-export checks.
8. Verify a clean installation, backup/rollback and a fresh watcher export.
9. Test the OctoPrint display on the actual target version/browser; record
   versions and the limitation that progress follows sent commands.
10. Perform supervised physical validation. Record which models/materials and
    firmware were tested; leave untested scope explicit.

## Build and publish

Run from the repository root, using Windows PowerShell 5.1, Python with setuptools,
and Node.js available on PATH:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\Test-Release.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\Build-Release.ps1
```

Build creates one **dist/PS3-Manual-Multicolor-<version>-All-in-One.zip**,
with the OctoPrint installable ZIP inside. Its **CHECKSUMS.sha256** lists every
other payload file; a separate **SHA256SUMS.txt** authenticates the outer ZIP
when compared with a trusted published digest. Hashes alone are not signatures.
Build refuses to overwrite an existing release ZIP.

Inspect the archive and scan for private paths, secrets, user projects, logs,
caches and generated print files. Commit the source, tag the exact commit,
and publish the bundle plus outer checksum and release notes.
Mark alpha-targeted releases as prereleases. A maintainer can use GitHub's
release UI or gh CLI; no automated publishing or credentials are embedded.

The repository's initial release preserves the earlier PS3 MIT and OctoPrint
AGPLv3 declarations. Retain component licenses and source links in future builds.
