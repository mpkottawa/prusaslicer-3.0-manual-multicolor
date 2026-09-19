# Release history

## 3.11A.08 — 2026-09-19

First public all-in-one release for PrusaSlicer 3.0.0-alpha11.

- Package the working watcher, same-layer preview/reordering, base detection,
  automatic top-layer reduction, next-colour start positioning and colour names.
- Include the clipboard palette and PS3 Lua diagnostics.
- Include saved MK4S manual printer and 0.20 mm HF print preset examples.
- Make launcher paths configurable through settings.json.
- Add backup-first installation, setup/update guides, checksums and ZIP building.
- Bundle the OctoPrint companion installer and corresponding source; 3.11a8 adds
  source/license links while retaining working 3.11a7 display behaviour.

The owner reported a successful physical MK4S 0.4 HF print. Postprocessor and
reorder logic are unchanged from that working installation. New packaging is
checked separately without modifying the live setup or starting a print.
