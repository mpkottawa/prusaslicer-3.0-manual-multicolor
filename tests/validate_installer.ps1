$ErrorActionPreference = 'Stop'
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('ps3-install-check-' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($testRoot)
# This isolated test process mocks PS3 presence; installation targets only a
# newly created temporary directory, never the user's live data directory.
function Get-Process { param($Name,$ErrorAction) return @() }
$installer = Join-Path $PSScriptRoot '..\tools\Install-PS3Tools.ps1'
$target = Join-Path $testRoot 'data'
& $installer -DataDirectory $target
$sentinel = Join-Path $target 'unrelated.txt'
[IO.File]::WriteAllText($sentinel,'retain unrelated file')
$printer = Join-Path $target 'presets\user\prusa-research-fff\PrusaResearch\printer-MK4S manual multicolor.yaml'
[IO.File]::WriteAllText($printer,'previous custom printer')
& $installer -DataDirectory $target -SkipPresets
if ([IO.File]::ReadAllText($printer) -ne 'previous custom printer') { throw 'SkipPresets replaced preset' }
& $installer -DataDirectory $target
$backups = @(Get-ChildItem -LiteralPath (Join-Path $target 'manual-multicolor-backups') -Recurse -File |
    Where-Object { $_.Name -eq 'printer-MK4S manual multicolor.yaml' -and [IO.File]::ReadAllText($_.FullName) -eq 'previous custom printer' })
if ($backups.Count -ne 1) { throw 'Previous preset not backed up exactly once' }
if ([IO.File]::ReadAllText($sentinel) -ne 'retain unrelated file') { throw 'Unrelated file changed' }
if ([IO.File]::ReadAllText($printer) -notmatch 'kind: printer') { throw 'Release preset missing' }
Write-Host 'PASS: clean temp install, preset preservation, update backup and unrelated-file preservation'
