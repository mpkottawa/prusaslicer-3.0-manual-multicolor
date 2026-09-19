# Release history

## 3.11A.08 (installer: 3.11a8) — 2026-09-19

- First public all-in-one release with PS3 tools and HF preset examples.
- Add public source/release link and include the existing AGPLv3 license text.
- Retain 3.11A.07 colour tracking, display and update behaviour.
- Owner reports a successful print with the preceding working setup.

## 3.11A.07 (installer: 3.11a7)

- Hide explicitly unused colours from the top navbar; keep the complete palette
  in the plugin tab.
- Double the red X stroke width over unused colours in the full palette.

## 3.11A.06 (installer: 3.11a6)

- Update plugin button opens Plugin Manager and its existing ZIP file picker.
- Preserve explicit Install confirmation, reauthentication and repository restrictions.
- Disable shortcut while printing/paused, without permissions, or if installer
  is unavailable/busy. Browser/version incompatibility offers manual Browse fallback.
- Offline update-flow and existing display/backend tests pass; live validation pending.

## 3.11A.05 (installer: 3.11a5)

- Colour names only in navbar, file palette and used-colour labels; no tool numbers.
- Large PRINTING / LOAD / READY colour indicator in navbar and tab, with a
  contrasting pulsing outline that keeps text fully visible.
- Retain unused-colour red crosses and layer separators. Honour reduced motion.

## 3.11A.04 (installer: 3.11a4)

- Thin black separators between layer rows, including compact body layers.
- Red X overlay on file slots explicitly marked unused, in both the tab and
  navbar. Labels remain visible; tooltips identify unused slots.
- Unknown usage is not crossed out, and unused slots never flash as active.

## 3.11A.01 (installer: 3.11a1) — 2026-09-19

Target: PrusaSlicer 3.0.0-alpha11, with this project's manual-colour postprocessor.

- Adopt Prusa-alpha-linked companion version numbering.
- Show companion version and target PrusaSlicer build in the tab.
- Retain full-stack chart, readable names, used-colour list and sent-command
  progress from the initial 0.1.0 package.
- Offline backend/frontend checks and the local 17-layer processed sample pass.
- Live OctoPrint/printer validation remains pending.

## 0.1.0 — 2026-09-19

Initial independent PS3 companion, based on the PS2 project's reference plugin.
# 3.11A.02

- Show the entire colour sequence without an internal scrollbar or hidden labels.
- Compact non-change rows to 16px, retaining 28px rows for colour changes.
- Long sequences expand the page instead of clipping layers.
# 3.11A.03

- Numbered file palette in the navbar and tab, including unused configured slots.
- Flash the uniquely identified current slot during printing, switching to the
  requested slot on M600 sent. M117 advance notice does not switch it early.
- Stop flashing on completion/cancel/failure; no flashing for an idle selection.
- This is sent-command tracking, not confirmation of physical nozzle parking.
