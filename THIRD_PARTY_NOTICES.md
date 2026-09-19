# Component licenses and attribution

- The original Lua bundle identifies its author as **amade** and declares
  **MIT**. That identifier/declaration is retained. The repository-level MIT
  license applies to this project's PS3 tools and documentation except the
  separately licensed components below.
- **octoprint-manual-multicolor/** retains its existing **AGPLv3** declaration.
  Its license is included in the installable ZIP and its full corresponding
  source is included in the all-in-one bundle. The UI links to this repository.
- **presets/** contains user modifications to Prusa-derived MK4S configuration
  and start/end G-code. Preserve Prusa Research attribution and **AGPLv3**
  terms for these derived settings; see **licenses/AGPL-3.0.txt**.
  Sources: [PrusaSlicer-settings](https://github.com/prusa3d/PrusaSlicer-settings)
  and [PrusaSlicer](https://github.com/prusa3d/PrusaSlicer).
  Changes disable actual MMU startup/loading/unloading, add manual M600 markers,
  select text export and disable wipe tower for this workflow.
- PrusaSlicer and OctoPrint are separate projects. Their binaries and firmware
  are not distributed here. Product names identify compatibility, not endorsement.

The existing license declarations are preserved rather than relicensing the
OctoPrint companion as MIT. No user model geometry is included.
