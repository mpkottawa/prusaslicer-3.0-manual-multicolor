param([string] $CancelledFile)
if ($CancelledFile) { throw 'Manual-colour export cancelled by user.' }
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$bundle = Join-Path $root 'plugins\com.amade.manual-multicolor\postprocess'
. (Join-Path $bundle 'Watch-ManualMulticolor.ps1') -LibraryOnly
$text = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'fixtures\three_layer_virtual_tools.gcode'))
$text += "`n; prusaslicer_config = end`n"
if (-not (Test-ManualExport 'test.gcode' $text)) { throw 'Valid export was rejected' }
if (Test-ManualExport 'test-manual.gcode' $text) { throw 'Output would be reprocessed' }
if (Test-ManualExport 'test.gcode' ($text.Replace('; prusaslicer_config = end', ''))) { throw 'Incomplete export accepted' }
if (Test-ManualExport 'test.gcode' ($text.Replace('; MANUAL_COLOUR_BOTTOM_LAYERS=1', ''))) { throw 'Unconfigured file accepted' }
if (Test-ManualExport 'test.gcode' ("; MANUAL_COLOUR_RESUME_AT_NEXT_START`n" + $text)) { throw 'Renamed processed file accepted' }
$fiveSlots = "; MANUAL_COLOUR_USED_SLOTS=5,1,3`n; extruder_colour = #000AFF;#FFFFFF;#E92233;#FFFF00;#008000`n"
if ((Get-UsedColourSuffix $fiveSlots) -ne 'Blue_Red_Green') { throw 'Unused slots or wrong slot order in filename' }
if ((Get-UsedColourSuffix ($fiveSlots + "; MANUAL_COLOUR_LABELS=Ocean Blue,White,Cherry Red,Yellow,Forest Green`n")) -ne 'Ocean-Blue_Cherry-Red_Forest-Green') { throw 'Explicit labels not honored' }
$temp = Join-Path ([IO.Path]::GetTempPath()) ('manual-watcher-test-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($temp) | Out-Null
$inputFile = Join-Path $temp 'source.gcode'
[IO.File]::WriteAllText($inputFile, $text)
$originalHash = (Get-FileHash -LiteralPath $inputFile).Hash
$oldHook = $env:MANUAL_COLOUR_TEST_ORDER
$env:MANUAL_COLOUR_TEST_ORDER = 'regression-without-ui'
try {
    $processor = Join-Path $bundle 'FlattenManualColoursAboveFirstLayer.ps1'
    $output = Convert-ExportCopy $inputFile $text $processor
    if ([IO.Path]::GetFileName($output) -ne 'source_Black_White_Red-manual.gcode') { throw 'Wrong output filename' }
    if ((Select-String -LiteralPath $output -Pattern '^M600').Count -ne 5) { throw 'Wrong pause count' }
    $second = Convert-ExportCopy $inputFile $text $processor
    if ($second -eq $output) { throw 'Existing output overwritten' }
    $cancelled = $false
    try { Convert-ExportCopy $inputFile $text $PSCommandPath | Out-Null }
    catch { $cancelled = $_.Exception.Message -eq 'Manual-colour export cancelled by user.' }
    if (-not $cancelled) { throw 'Cancellation did not propagate' }
    if (@(Get-ChildItem -LiteralPath $temp -Filter '*.tmp' -Force).Count) { throw 'Pending files left behind' }
    if (@(Get-ChildItem -LiteralPath $temp -Filter '*.gcode').Count -ne 3) { throw 'Cancellation published output' }
    if ((Get-FileHash -LiteralPath $inputFile).Hash -ne $originalHash) { throw 'Original changed' }
    Write-Host 'PASS: eligibility, incomplete exports, repeat prevention, processing, collision handling, cancellation, source preservation'
} finally { $env:MANUAL_COLOUR_TEST_ORDER = $oldHook }
