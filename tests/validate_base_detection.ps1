param([Parameter(Mandatory=$true)][string]$GcodePath)
$ErrorActionPreference='Stop'
$processor=Join-Path $PSScriptRoot '..\plugins\com.amade.manual-multicolor\postprocess\FlattenManualColoursAboveFirstLayer.ps1'
$dir=Join-Path ([IO.Path]::GetTempPath()) ('ps3-base-test-' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($dir)
$target=Join-Path $dir 'green-base.gcode'
Copy-Item -LiteralPath $GcodePath -Destination $target
$before=(Get-FileHash -LiteralPath $GcodePath).Hash
$previousOrder=$env:MANUAL_COLOUR_TEST_ORDER
$env:MANUAL_COLOUR_TEST_ORDER='unchanged'
try { & $processor $target } finally { $env:MANUAL_COLOUR_TEST_ORDER=$previousOrder }
$text=[IO.File]::ReadAllText($target)
if($text -notmatch '(?m)^; MANUAL_COLOUR_BASE_SLOT=3\s*$') { throw 'Expected slot 3 body' }
if($text -notmatch '(?m)^; MANUAL_COLOUR_TOP_LAYERS=0\s*$') { throw 'Expected no top multicolour' }
$segments=[regex]::Matches($text,'(?m)^M118 MCP_SEGMENT L=(\d+) S=\d+ C="([^"]+)"')
foreach($segment in $segments) {
    if([int]$segment.Groups[1].Value -ge 3 -and $segment.Groups[2].Value -ne 'Green') { throw 'Wrong body layer colour' }
}
if($text -match '(?m)^T\d+\s*$') { throw 'Virtual tool command remains' }
if(@([regex]::Matches($text,'(?m)^M600\b')).Count -ne 4) { throw 'Expected four automatically arranged pauses' }
$l=0
foreach($line in ($text -split "`n")) { if($line.Trim() -eq ';LAYER_CHANGE'){$l++}; if($l -ge 3 -and $line -match '^M600\b'){throw 'Unexpected body-layer pause'} }
if((Get-FileHash -LiteralPath $GcodePath).Hash -ne $before) { throw 'Source changed' }
"PASS: slot 3 Green, top 0, all body segments Green, no virtual tool commands; artifact $target"
