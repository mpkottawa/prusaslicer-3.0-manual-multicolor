[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$releaseRoot = Split-Path $PSScriptRoot
function Invoke-Checked([string]$Command,[string[]]$Arguments) {
    & $Command @Arguments
    if ($LASTEXITCODE -ne 0) { throw "Check failed: $Command $Arguments" }
}
Push-Location $releaseRoot
try {
    foreach ($file in Get-ChildItem -Recurse -File -Filter '*.ps1') {
        $parseErrors=$null; $parseTokens=$null
        [void][Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$parseTokens,[ref]$parseErrors)
        if ($parseErrors.Count) { throw "PowerShell syntax: $($file.FullName): $parseErrors" }
    }
    foreach ($test in @('validate_bundle.py','validate_release.py','validate_postprocessor.py')) {
        Invoke-Checked 'python' @("tests\$test")
    }
    foreach ($test in @('validate_colour_names.ps1','validate_watcher.ps1','validate_free_reorder.ps1')) {
        Invoke-Checked 'powershell.exe' @('-NoProfile','-STA','-ExecutionPolicy','Bypass','-File',"tests\$test")
    }
    $testFolder = Join-Path ([IO.Path]::GetTempPath()) ('ps3-release-tests-' + [guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($testFolder)
    $fixture = Join-Path $testFolder 'synthetic-green-base.gcode'
    & .\tests\New-TestFixture.ps1 -Destination $fixture
    foreach ($test in @('validate_base_detection.ps1','validate_preview_controls.ps1')) {
        Invoke-Checked 'powershell.exe' @('-NoProfile','-STA','-ExecutionPolicy','Bypass','-File',"tests\$test",'-GcodePath',$fixture)
    }
    Invoke-Checked 'powershell.exe' @('-NoProfile','-ExecutionPolicy','Bypass','-File','tools\Install-PS3Tools.ps1','-DataDirectory',(Join-Path $testFolder 'not-created'),'-WhatIf')
    if (Test-Path -LiteralPath (Join-Path $testFolder 'not-created')) { throw 'Installer WhatIf wrote files.' }
    Invoke-Checked 'powershell.exe' @('-NoProfile','-ExecutionPolicy','Bypass','-File','tests\validate_installer.ps1')
    Invoke-Checked 'python' @('-m','unittest','discover','-s','octoprint-manual-multicolor\tests','-p','test_*.py')
    Invoke-Checked 'node' @('octoprint-manual-multicolor\tests\test_display.js')
    Invoke-Checked 'node' @('octoprint-manual-multicolor\tests\test_update.js')
    Write-Host 'PASS: release checks completed. No print was started.'
} finally { Pop-Location }
