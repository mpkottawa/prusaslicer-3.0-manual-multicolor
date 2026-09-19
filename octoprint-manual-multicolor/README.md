# PS3 Manual Multicolor — OctoPrint companion

Independent companion for the PrusaSlicer 3 Manual Multicolor postprocessor.
Based on the local Manual Colour Prompts plugin, with a separate plugin ID so
updates do not overwrite the reference implementation.

## Install

1. Disable the old **Manual Colour Prompts** plugin to avoid duplicate displays.
2. In OctoPrint, open Settings > Plugin Manager > Get More > From file.
3. Install `OctoPrint-manual_multicolor_ps3-3.11a8.zip` from the all-in-one
   release's `octoprint` folder (or this source folder's `dist` after building).
4. Restart OctoPrint and refresh the browser.
5. Export through the PS3 watcher, confirm its preview, and upload/select the
   resulting `*-manual.gcode`, not the unprocessed original export.
6. Open the **PS3 Manual Multicolor** tab before starting a print.

## Quick ZIP updates (3.11A.06 onward)

Click **Update plugin…** in the PS3 Manual Multicolor tab. This opens Settings /
Plugin Manager / Get More and invokes its native file chooser in the same click.
Choose the new companion ZIP, then click **Install** in OctoPrint's installer.
Restart when prompted and refresh the browser. Install 3.11A.06 manually once to
get this shortcut; it cannot appear in an older installed version.

The shortcut is disabled while printing/paused, without install/manage permissions,
or when Plugin Manager reports it cannot install. It never uploads, installs,
restarts, unlocks restrictions or dismisses authentication automatically. If
OctoPrint asks you to reauthenticate, or the browser prevents the automatic
chooser, complete that prompt and use **Browse** in the normal installer.
Missing/changed Plugin Manager controls fall back to manual instructions.

Integration was checked against the [OctoPrint 1.11.3 Plugin Manager source](https://github.com/OctoPrint/OctoPrint/blob/1.11.3/src/octoprint/plugins/pluginmanager/static/js/pluginmanager.js).
Offline tests cover picker dispatch and guards; live-host/browser validation is
still required because this shortcut depends on OctoPrint's frontend controls.

## Display

- The top navbar hides explicitly unused colours. The tab keeps all configured
  file slots as colour names (without tool numbers).
  A large PRINTING / LOAD / READY indicator uses a contrasting pulsing outline,
  keeping the colour name readable throughout. Reduced-motion mode uses a steady outline.
  Slots explicitly marked unused have a thick red X in the tab; unknown usage is
  neither hidden nor crossed out.
  During printing the current colour flashes. On M600 sent it switches to the
  requested colour, then keeps flashing that colour when printing continues.
  M117 advance notices do not switch the flashing slot. Idle/completed jobs do
  not flash. Physical nozzle parking is not confirmed by this display.
  If multiple used slots have indistinguishable names, no slot is guessed;
  assign distinct MANUAL_COLOUR_LABELS to identify them unambiguously.
- Initial and next colour names, retaining the exact hex colour swatches.
- Used slots only, in slot order when MANUAL_COLOUR_USED_SLOTS metadata exists.
  Legacy files show distinct colours in first-use order instead.
- All layers remain visible with no internal scrollbar. Non-change rows are
  16px tall; colour-change rows stay 28px tall. Labels remain visible. Very tall
  stacks expand the page, so the page itself may still need scrolling.
  Thin black lines separate adjacent layers, including single-colour body rows.
- Live M117/M600 prompts and MCP_SEGMENT highlighting.
- Unrelated uploads do not replace the selected print's schedule.

Hex-to-name conversion is approximate (e.g. shades of blue become Blue).
The plugin is informational only: it never inserts G-code, changes printer
settings, pauses, resumes, or starts printing. Progress follows outgoing
commands, which may be buffered; always confirm filament changes on the printer.
Firmware must support M600. No Palette/MMU hardware control is provided.
Local OctoPrint-hosted plain-text G-code is supported, not SD-card-only jobs or
binary BGCODE. Restarting OctoPrint mid-print cannot reconstruct live progress.

## Development

`python -m unittest discover -s tests -p "test_*.py"`

`node tests/test_display.js`

`node tests/test_update.js`

`python setup.py sdist --formats=zip`

## Versions and updates

Current release: **3.11A.08**, targeting **PrusaSlicer 3.0.0-alpha11**.
The Python installer spelling is `3.11a8`; both identify the same release.

- `3` = PrusaSlicer major version.
- `11A` = alpha11 compatibility line.
- `.01` = our companion revision for that line.
- Next companion fix for alpha11: `3.11A.09` / `3.11a9`.
- First release targeting alpha12: `3.12A.01` / `3.12a1`.

Keep the plugin identifier `manual_multicolor_ps3` unchanged so new ZIPs update
this plugin in place. Do not install a separate plugin per alpha. Retain older
ZIPs in `dist` for rollback. Updates are manual through Plugin Manager; no
automatic update server or Prusa release monitor is configured.

Before releasing for another Prusa build, inspect its export/marker changes,
test the PS3 postprocessor and this companion with representative G-code,
update `version.py` and `CHANGELOG.md`, then build a new ZIP. An alpha number
in the version is a target, not a claim of live printer validation. Revisit the
numbering before beta/stable releases or a new PrusaSlicer minor series.

Local tests do not substitute for OctoPrint/printer validation.
