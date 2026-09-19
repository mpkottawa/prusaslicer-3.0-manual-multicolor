# PrusaSlicer 3 Manual Multicolor

Manual same-layer filament swaps on a single-nozzle printer, with an export
preview and an optional OctoPrint colour-progress display. No MMU hardware is
required: the MK4S MMU3 profile supplies virtual colour slots only.

**Release 3.11A.08 — targets PrusaSlicer 3.0.0-alpha11 on Windows.**
This is a community project, not an official Prusa or OctoPrint extension.

The owner reported a successful physical print on an MK4S with a 0.4 mm HF nozzle
on 2026-09-19. That validates that workflow, not every model, printer, material,
firmware version or future PrusaSlicer release.

## One download

Get **PS3-Manual-Multicolor-3.11A.08-All-in-One.zip** from
[Releases](https://github.com/mpkottawa/prusaslicer-3.0-manual-multicolor/releases).

Extract it on Windows. It includes:

- Export watcher, colour/order preview and clipboard colour palette.
- PS3 Lua diagnostics and example MK4S manual / 0.20 mm HF presets.
- **octoprint/OctoPrint-manual_multicolor_ps3-3.11a8.zip** for Plugin Manager.
- Full companion source, licenses, setup/update instructions and test/build tools.
- Compatibility metadata and checksums.

Do not upload the outer all-in-one ZIP to OctoPrint. Install the ZIP inside
the **octoprint** folder. PrusaSlicer, OctoPrint, firmware, models and printable
G-code are not included.

## Setup and everyday use

Follow the [installation and profile guide](docs/SETUP.md).

1. While PS3 is closed, run **install-ps3-tools.cmd** to install the optional Lua
   tools and example presets. Existing target files are backed up first.
2. Edit **settings.json** for your PrusaSlicer executable and export folder.
3. Run **start-auto-multicolor.cmd**. Wait for **Started watching** and leave
   its console open (minimizing is fine).
4. Select **MK4S manual multicolor**, **0.4 HF** hardware and the
   **manual multicolor 2.0** print preset. Assign the model's colours.
5. Slice and export plain-text G-code into the watched folder.
6. Inspect the preview, reorder supported bottom-layer colour blocks if needed,
   then click **Write G-code**.
7. Check and print only the resulting **-manual.gcode**.

There is **no per-print-profile script field required**. The watcher handles
GUI exports because alpha11 does not reliably invoke external postprocessing.
Existing files are ignored at watcher startup; export again to open the preview.

## Features

- Preserve each colour's geometry when swapping bottom-layer print order.
- Detect an unambiguous single-colour body; the base need not be slot 1.
- Finish the last bottom colour layer with the base where possible.
- Reduce requested top colour layers to zero when they contain only base.
- Clickable layer/colour plan with the initial filament and pause count.
- Broad colour names and optional custom labels.
- Output filenames contain only used colours, in slot order.
- Lift/travel to the incoming colour's start before M600; the first-layer
  purge-strip sequence may still run after the change. Firmware controls parking.
- Source exports are unchanged; cancellation creates no output.
- Clipboard colour palette: **quick-colors.cmd**.
- OctoPrint: conspicuous current/load indicator, compact all-layer chart,
  unused-colour crosses and a ZIP-update shortcut.

## Supported scope and limits

Windows PowerShell 5.1 and PrusaSlicer **3.0.0-alpha11** are the target.
The supplied print preset is for **MK4S 0.4 HF**, based on Prusa preset repository
**1.0.18**. Later repository versions are not verified. Select HF only if that
is the physically installed nozzle.

Use text G-code, absolute XYZ, relative E, M600-capable firmware, no wipe tower
and no MMU startup/loading commands. The hardware profile provides five virtual
slots. Bottom/top colour limits support 0–2 layers each. This is not a general
replacement for arbitrary full-height multicolour printing.

Free bottom-layer reordering requires a following body layer and one contiguous
block per colour per bottom layer. Unsupported coordinate modes, MMU unloading,
skirt/brim/support blocks and incompatible initial temperatures/materials are
rejected. Ambiguous multicolour bodies are not silently flattened by majority.
Reordering also refuses toolpaths whose retraction state cannot be safely
reconstructed; a successful normal export does not guarantee it is reorderable.

OctoPrint follows **sent commands**, not confirmed nozzle position. It does not
start, pause, resume or modify a print. Local text-G-code jobs are supported;
SD-only jobs and binary BGCODE are not.

Check initial filament, colour order, nozzle flag, temperatures and clearance
before a supervised first print. Do not combine this workflow with P2PP/Palette.

## Updates and development

See [setup/updates](docs/SETUP.md), [testing](docs/TESTING.md),
[release maintenance](docs/RELEASING.md), [changelog](CHANGELOG.md) and
[OctoPrint documentation](octoprint-manual-multicolor/README.md).

Versions track Prusa compatibility: **3.11A.08** is the eighth project revision
for PS3 alpha11; the OctoPrint installer uses **3.11a8**. New Prusa releases
require inspection and testing, not just renaming the version.

## Licenses and attribution

PS3 tools retain the original bundle's MIT declaration: [LICENSE](LICENSE).
The OctoPrint companion retains [AGPLv3](octoprint-manual-multicolor/LICENSE).
Presets contain Prusa-derived configuration/G-code; see
[third-party notices](THIRD_PARTY_NOTICES.md). Original author identifiers are
preserved. No PrusaSlicer or OctoPrint binaries are redistributed.
