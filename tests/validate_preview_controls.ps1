param([Parameter(Mandatory=$true)][string]$GcodePath)
$ErrorActionPreference = 'Stop'
$WarningPreference = 'Stop'
$processor = Join-Path $PSScriptRoot '..\plugins\com.amade.manual-multicolor\postprocess\FlattenManualColoursAboveFirstLayer.ps1'
$source = [IO.File]::ReadAllText($processor)
$replacement = @'
        # Exercise real WinForms event bindings without showing/accepting a dialog.
        $testCell = @($bar.Controls | Where-Object { $_ -is [Windows.Forms.Button] -and $_.Tag.Layer -eq 2 -and $_.Tag.Tool -eq 0 })[0]
        $clickMethod = [Windows.Forms.Button].GetMethod('OnClick', [Reflection.BindingFlags]'Instance,NonPublic')
        [void]$clickMethod.Invoke($testCell, @([EventArgs]::Empty))
        if ($sliceCanvas.Tag.Layer -ne 2 -or $sliceCanvas.Tag.Tool -ne 0) { throw 'Cell selection callback failed' }
        if (-not $finishBase.Enabled) { throw 'Finish-base button unexpectedly disabled' }
        [void]$clickMethod.Invoke($finishBase, @([EventArgs]::Empty))
        if (($layerSequenceTools[2] -join ',') -ne '1,0,2') { throw 'Finish-base callback failed' }
        if (($layerSequenceTools[1] -join ',') -ne '0,2,1') { throw 'Automatic continuity arrangement failed' }
        & $moveGridCell ([pscustomobject]@{Layer=1;Index=1}) ([pscustomobject]@{Layer=1;Index=2})
        if (($layerSequenceTools[1] -join ',') -ne '0,1,2') { throw 'Last cell was not movable' }
        & $moveGridCell ([pscustomobject]@{Layer=1;Index=1}) ([pscustomobject]@{Layer=1;Index=2})
        if ($heading.Text -notmatch 'Manual pauses: 4') { throw 'Pause summary was not refreshed' }
        & $moveGridCell ([pscustomobject]@{Layer=1;Index=0}) ([pscustomobject]@{Layer=1;Index=1})
        if (($layerSequenceTools[1] -join ',') -ne '2,0,1') { throw 'First cell was not movable' }
        if ($scheduleBox.Text -notmatch 'Initial filament: Green') { throw 'Initial filament summary was not refreshed' }
        $checkedCells = 0
        foreach ($testSize in @([Drawing.Size]::new(1040,640), [Drawing.Size]::new(1320,760), [Drawing.Size]::new(1700,1000))) {
            $preview.Size = $testSize
            & $layoutPreview
            # Hidden test forms need explicit HWND creation for native hit tests.
            [void]$bar.Handle
            foreach ($control in $bar.Controls) { [void]$control.Handle }
            foreach ($cell in @($bar.Controls | Where-Object { $_ -is [Windows.Forms.Button] })) {
                # Hit-test near every corner and centre in panel coordinates,
                # then invoke the actual returned button's click event.
                foreach ($point in @(
                    [Drawing.Point]::new($cell.Left + 1, $cell.Top + 1),
                    [Drawing.Point]::new($cell.Right - 2, $cell.Top + 1),
                    [Drawing.Point]::new($cell.Left + 1, $cell.Bottom - 2),
                    [Drawing.Point]::new($cell.Right - 2, $cell.Bottom - 2),
                    [Drawing.Point]::new($cell.Left + [int]($cell.Width / 2), $cell.Top + [int]($cell.Height / 2))
                )) {
                    $hit = $bar.GetChildAtPoint($point)
                    if (-not [object]::ReferenceEquals($hit, $cell)) { throw "Wrong hit target at $point for layer $($cell.Tag.Layer) tool $($cell.Tag.Tool)" }
                    [void]$clickMethod.Invoke($hit, @([EventArgs]::Empty))
                    if ($sliceCanvas.Tag.Layer -ne $cell.Tag.Layer -or $sliceCanvas.Tag.Tool -ne $cell.Tag.Tool) { throw "Wrong selection for layer $($cell.Tag.Layer) tool $($cell.Tag.Tool)" }
                }
                $checkedCells++
            }
        }
        Write-Host "PASS: $checkedCells cells, five hit points each, three window sizes after reorder"
        $preview.Dispose()
        throw 'Manual-colour export cancelled by user.'
'@
if (-not $source.Contains('$choice = $preview.ShowDialog()')) { throw 'Preview test insertion point missing' }
$source = $source.Replace('$choice = $preview.ShowDialog()', $replacement)
$before = (Get-FileHash -LiteralPath $GcodePath).Hash
try {
    & ([scriptblock]::Create($source)) $GcodePath
    throw 'Expected cancellation after UI checks'
} catch {
    if ($_.Exception.Message -ne 'Manual-colour export cancelled by user.') { throw }
}
if ((Get-FileHash -LiteralPath $GcodePath).Hash -ne $before) { throw 'UI test modified the input' }
Write-Host 'PASS: cell click, finish-base button, refreshed pause count, cancellation preserves source'
