[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [string]$DataDirectory = (Join-Path $env:APPDATA 'PrusaSlicer3-dev'),
    [switch]$SkipPresets
)
$ErrorActionPreference = 'Stop'
$releaseRoot = Split-Path $PSScriptRoot
if (-not $WhatIfPreference -and (Get-Process -Name PrusaSlicer -ErrorAction SilentlyContinue)) {
    throw 'Close PrusaSlicer before installing. Your open project has not been changed.'
}
$DataDirectory = [IO.Path]::GetFullPath($DataDirectory)
$backupRoot = Join-Path $DataDirectory ('manual-multicolor-backups\' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0,8))
$copies = @()
$pluginRoot = Join-Path $releaseRoot 'plugins\com.amade.manual-multicolor'
foreach ($file in Get-ChildItem -LiteralPath $pluginRoot -Recurse -File) {
    if ($file.Extension -in @('.lua','.json','.ps1','.cmd')) {
        $relative = $file.FullName.Substring($pluginRoot.Length).TrimStart('\')
        $copies += @{Source=$file.FullName; Relative=('lua\com.amade.manual-multicolor\' + $relative)}
    }
}
if (-not $SkipPresets) {
    foreach ($file in Get-ChildItem -LiteralPath (Join-Path $releaseRoot 'presets') -Filter '*.yaml' -File) {
        $copies += @{Source=$file.FullName; Relative=('presets\user\prusa-research-fff\PrusaResearch\' + $file.Name)}
    }
}
foreach ($copy in $copies) {
    $target = Join-Path $DataDirectory $copy.Relative
    if ($PSCmdlet.ShouldProcess($target, 'Back up existing file, then install release copy')) {
        if (Test-Path -LiteralPath $target) {
            $backup = Join-Path $backupRoot $copy.Relative
            [void][IO.Directory]::CreateDirectory((Split-Path $backup))
            Copy-Item -LiteralPath $target -Destination $backup
        }
        [void][IO.Directory]::CreateDirectory((Split-Path $target))
        Copy-Item -LiteralPath $copy.Source -Destination $target -Force
    }
}
if ($WhatIfPreference) { Write-Host 'Preview only: nothing installed.'; return }
Write-Host "Installed PS3 tools into $DataDirectory"
if (Test-Path -LiteralPath $backupRoot) { Write-Host "Previous files backed up in $backupRoot" }
Write-Host 'Next: edit settings.json, then run start-auto-multicolor.cmd.'
Write-Host 'Select the manual presets and correct nozzle. No print was started.'
