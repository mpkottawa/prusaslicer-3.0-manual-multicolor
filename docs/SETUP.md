# Windows setup — PS3 alpha11 / MK4S 0.4 HF

## Requirements

- Windows with Windows PowerShell 5.1 (WinForms is required).
- PrusaSlicer 3.0.0-alpha11, installed separately.
- Prusa MK4S/MMU3 hardware definitions. Bundled presets refer to parent IDs
  checked against Prusa preset repository 1.0.18.
- Physical MK4S with a 0.4 mm HF nozzle and M600-capable firmware.
- Compatible PLA temperatures/materials when reordering the initial colour.
- Optional: OctoPrint for the progress display.

This package does not install PrusaSlicer, firmware or vendor repositories.
Do not use its HF print preset with a standard-flow nozzle.

## Install

1. Extract the all-in-one ZIP into a permanent folder.
2. Save your work and close PrusaSlicer.
3. Run **install-ps3-tools.cmd**. It installs the Lua tools and two example
   user presets into **%APPDATA%\PrusaSlicer3-dev**.
   Existing destination files are backed up under **manual-multicolor-backups**
   in that data directory. Other user presets and stock files are unchanged.
4. For a different PS3 data directory, run from the extracted folder:

   ```powershell
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\Install-PS3Tools.ps1 -DataDirectory "D:\MyPS3Data"
   ```

   Add **-WhatIf** to preview without changes, or **-SkipPresets** to install
   only Lua tools. The launcher opens PS3's default data directory; for a custom
   one, first open PS3 using your usual custom-data-directory shortcut.
5. Edit **settings.json**:
   - **slicer_path**: full path to your alpha11 PrusaSlicer.exe.
   - **export_folder**: where you will export raw G-code. Environment variables
     such as **%USERPROFILE%** are expanded. Double backslashes in JSON.
     The launcher creates this folder if needed.
6. Run **start-auto-multicolor.cmd**. It keeps an existing session using that
   executable, or opens PS3, then starts the watcher.
   Wait for a new **Started watching <your folder>** message.
7. Keep the console open (minimizing is fine).

No administrator privileges, startup task, printer connection or print-start
command is required.

## Select the profiles

| Item | Selection |
| --- | --- |
| Hardware | Prusa MK4S MMU3 0.4 HF |
| Printer preset | MK4S manual multicolor |
| Print preset | manual multicolor 2.0 |
| Filament | Compatible HF PLA for every used slot |

MMU3 provides five virtual slots. The custom printer preset removes real
MMU startup/load/unload commands; it does not control an MMU.

Check wipe tower **off**, prime all printing extruders **off**, binary G-code
**off**, single-extruder multimaterial **on**, and relative extrusion **on**.
The example uses 0.20 mm layers, 20% cubic infill, four bottom and six top
structural solid layers. These are examples, not a universal model recipe.
Structural solid layers are separate from the manual colour-layer limits.

For another print profile, save a copy of this HF profile and adjust quality
settings. Keep the manual **printer** preset and settings above. No per-profile
postprocessing script is needed for the watcher.

If presets are missing, check data directory, alpha11 hardware definitions and
HF selection. Do not substitute a stock MMU printer preset: it has real MMU
commands. Newer Prusa builds or repository IDs require compatibility checks.

## Model and export

1. Load aligned parts as one multipart model, or use painted regions. Assign
   each part/region to its intended virtual slot.
2. The body/base can be any slot. Detection uses an unambiguous single-colour
   body, not simply the first or darkest slot.
3. Slice and inspect PS3 Preview by colour/tool.
4. Export **text .gcode** into the folder shown by the watcher.
5. Inspect the popup. Click a colour to view its paths; drag between cells in
   a supported bottom-layer row to swap order, not colour assignment.
   Check initial filament and pause count after reordering.
6. Click **Write G-code**. The output is
   **<name>_<used-colours-in-slot-order>-manual.gcode**.
   Existing outputs get a numeric suffix; the original export is unchanged.
7. Inspect the final file. Print only the processed **-manual.gcode**.

The supplied Start G-code begins with:

```gcode
; MANUAL_COLOUR_BOTTOM_LAYERS=2
; MANUAL_COLOUR_TOP_LAYERS=2
; MANUAL_COLOUR_EXPORT_CONFIRM=1
```

Requested top layers become zero when they contain only the detected base.
Where the last bottom row contains the base, automatic arrangement puts it
last so the body can continue without another change.
Unsupported or ambiguous layouts are not automatically made safe.

Optional directives:

```gcode
; MANUAL_COLOUR_BASE_SLOT=3
; MANUAL_COLOUR_LABELS=Black,Yellow,Green,Red,White
```

Slots are one-based. Override the base only when it matches the intended body.
Labels name slots, not order of use. Omit these lines to use automatic detection
and broad colour names. **quick-colors.cmd** copies basic hex values for pasting
into PS3's colour field; it does not edit PS3 directly.

## OctoPrint installation and updates

In the all-in-one ZIP, find:
**octoprint/OctoPrint-manual_multicolor_ps3-3.11a8.zip**.

1. Disable the older Manual Colour Prompts plugin if present, to avoid duplicates.
2. Open Settings > Plugin Manager > Get More > From file.
3. Choose the **inner OctoPrint ZIP**, not the all-in-one ZIP, and install.
4. Restart OctoPrint and refresh the browser.
5. Upload/select the processed G-code and inspect PS3 Manual Multicolor.

The indicator switches on sent M600 commands, not confirmed nozzle parking.
Printer prompts remain authoritative. Future updates can use the companion's
**Update plugin** button to open Plugin Manager's ZIP chooser; install and
restart still need your confirmation.

## Updating PS3 or this package

Before changing PrusaSlicer versions, read the new package's **release.json**
and release notes. An alpha11 package is not automatically compatible with
alpha12/beta/stable. Keep the working version until the new target is validated.

1. Back up your project and custom profiles.
2. Stop the old watcher from its tray icon; close previews and PS3.
3. Extract the new all-in-one release into a separate versioned folder.
4. Configure its settings.json, preserving your executable/export-folder choices.
5. Run its installer. Existing target files are backed up automatically.
6. Install the new inner OctoPrint ZIP through the same plugin identifier.
7. Restart PS3/OctoPrint and start only the new watcher.
8. Re-slice, inspect the new preview/output and do a supervised validation print.

User-customized supplied presets are backed up but replaced by installation.
Use **-SkipPresets** to preserve them and compare changes manually.
No automatic downloads, upgrades, firmware changes or printing are performed.

## Troubleshooting and rollback

- **No popup:** check a fresh Started watching message, matching export folder,
  correct manual printer preset and text G-code. Export again after startup.
- **Popup behind PS3:** check taskbar/Alt+Tab; avoid repeated exports while a
  preview is waiting.
- **Launcher failure:** retain the console error. Running
  **tools\Start-ManualMulticolor.ps1 -CheckOnly** checks paths without starting
  apps or changing files.
- Logs: **%LOCALAPPDATA%\PrusaManualMulticolor\watcher.log** and **preview.log**.
  Logs are local and can contain filenames.
- **Rollback:** stop watcher, close PS3, restore affected files from the
  installer backup folder or reinstall the previous release. Keep project
  backups separately. Reinstall the prior companion ZIP if needed.

The advanced **run-manual-multicolor.cmd** rewrites its input **in place**.
Do not combine it with the watcher or use your only original export with it.
