# 3.11A.08 — PrusaSlicer 3.0.0-alpha11 Manual Multicolor

First public all-in-one release. The owner reports a successful physical print
on an MK4S with a 0.4 mm HF nozzle. Marked prerelease because it targets PS3 alpha11.

Download **PS3-Manual-Multicolor-3.11A.08-All-in-One.zip** and extract it.
It includes the Windows tools, HF preset examples, setup/update instructions,
test/build tools, licenses, full source and the separate OctoPrint installer at
**octoprint/OctoPrint-manual_multicolor_ps3-3.11a8.zip**.
Upload only that inner ZIP to OctoPrint Plugin Manager.

Features: automatic export preview, geometry-preserving bottom colour reordering,
base detection independent of slot number, automatic top-layer reduction,
next-colour start positioning, used-colour filenames, clipboard palette and
OctoPrint progress display.

The postprocessor/reorder logic is unchanged from the successful-print setup.
Packaging adds portable paths, backup-first installation, documentation and
license/source links. Live installations are not updated automatically.

No per-profile script field is needed. Start the watcher, wait for Started
watching, and export text G-code into its folder. Print only **-manual.gcode**.

See README.md, docs/SETUP.md and docs/TESTING.md for limits and verification.
OctoPrint tracks sent commands, not physical nozzle position.
No slicer/firmware binaries, personal models or printable G-code are included.
