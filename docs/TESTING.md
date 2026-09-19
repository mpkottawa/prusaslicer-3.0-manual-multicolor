# Verification

## Automated checks

Run from the repository root on Windows with Windows PowerShell 5.1, Python
(setuptools required for packaging), and Node.js on PATH:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\Test-Release.ps1
```

Checks include:

- PS3 bundle structure and PowerShell syntax.
- Colour naming and explicit labels.
- Watcher eligibility, incomplete files, repeat prevention, collision handling,
  cancellation and original-file preservation.
- All 36 permutations of two three-colour rows: deposited geometry, extrusion
  and feedrates must remain unchanged for each colour.
- Full transformer output: expected initial filament, M600 counts and no
  standalone virtual T commands.
- Base detection, top reduction and hidden WinForms click/hit testing using
  a synthetic fixture. No user dialogs are accepted.
- OctoPrint parser, selected-file isolation, display and ZIP-update guards.
- Version, preset and packaging consistency; installer dry run.

Synthetic fixtures are test data, **not printable G-code**.
Tests write temporary artifacts but do not upload, connect to a printer or print.
The hidden WinForms checks are not a substitute for visual/manual testing.

For a real raw export, run (source remains unchanged):

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\validate_free_reorder.ps1 -GcodePath "D:\exports\raw.gcode"
```

The dedicated base/UI tests expect the bundled three-colour Green-base layout;
do not treat their exact pause/colour assertions as valid for every model.

## Physical validation record

On 2026-09-19 the owner reported: **Print was perfect**.
Known setup: MK4S, 0.4 mm HF nozzle, PS3 3.0.0-alpha11, manual colour workflow,
Black/Grey model and OctoPrint companion. Exact live firmware and OctoPrint
version were not recorded. This statement is a user-reported result, not
independent certification or broad compatibility testing.

The released processor and reorder helper retain the exact working source.
Packaging, configurable launcher, installer, metadata and documentation are
new. They are checked without modifying the owner's live setup.

The successful Black/Grey raw export triggers the existing optional-reorder
safety guard: an extrusion begins while the reordering model still considers
the extruder retracted. Arbitrary block reordering is therefore rejected for
that file; the successful print does not establish free-reordering support for
it. The default export workflow and the tested synthetic reordering cases are
separate checks.

The actual raw export also passes normal processing on a temporary copy:
four M600 changes, 0.4 HF nozzle flag retained, no standalone virtual T commands,
and unchanged original file. It requests one bottom and two top colour layers;
the supplied profile examples default to two bottom and two top.

Release validation also reruns the full suite from the extracted all-in-one ZIP
and builds a wheel from its inner OctoPrint ZIP in an isolated build environment.
This checks packaging without installing it on the live OctoPrint host.
