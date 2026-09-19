param([string]$GcodePath)
$ErrorActionPreference='Stop'
$processor=Join-Path $PSScriptRoot '..\plugins\com.amade.manual-multicolor\postprocess\FlattenManualColoursAboveFirstLayer.ps1'
$ast=[Management.Automation.Language.Parser]::ParseFile($processor,[ref]$null,[ref]$null)
foreach($name in @('Add-GcodeRange','Format-GcodeNumber')) {
    $fn=$ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name},$true)
    Invoke-Expression $fn.Extent.Text
}
function Get-ToolLabel($Tool){return "Tool$Tool"}
. (Join-Path (Split-Path $processor) 'ReorderColourBlocks.ps1')
function Get-Traces([string[]]$Lines) {
    $l=0;$t=0;$x=0.;$y=0.;$z=0.;$f=0.;$map=@{}
    $processed=[bool]@($Lines | Where-Object {$_ -match '^; MANUAL_COLOUR_BLOCK tool='}).Count;$inBlock=$false
    foreach($line in $Lines) {
        if($line -eq ';LAYER_CHANGE'){$l++;continue}
        if($l -gt 2){break}
        if($line -match '^T(\d+)'){$t=[int]$Matches[1]}
        if($line -eq '; MANUAL_COLOUR_TOOLCHANGE'){$inBlock=$false}
        if($line -match '^; MANUAL_COLOUR_BLOCK tool=(\d+)'){$t=[int]$Matches[1];$inBlock=$true}
        if($line -notmatch '^G([0123])\s'){continue}
        $g=$Matches[1];$v=@{}
        foreach($m in [regex]::Matches(($line -split ';')[0],'\b([XYZEFIJKR])([-+0-9.]+)')){$v[$m.Groups[1].Value]=[double]$m.Groups[2].Value}
        $nx=if($v.ContainsKey('X')){$v.X}else{$x};$ny=if($v.ContainsKey('Y')){$v.Y}else{$y};$nz=if($v.ContainsKey('Z')){$v.Z}else{$z}
        if($v.ContainsKey('F')){$f=$v.F}
        if(($inBlock -or -not $processed) -and $l -gt 0 -and $v.E -gt 0 -and ($nx -ne $x -or $ny -ne $y -or $g -in @('2','3'))) {
            $key="$l/$t";if(-not $map.ContainsKey($key)){$map[$key]=[Collections.Generic.List[string]]::new()}
            $map[$key].Add((@($g,$x,$y,$z,$nx,$ny,$nz,$v.E,$f,$v.I,$v.J,$v.R) -join '/'))
        }
        $x=$nx;$y=$ny;$z=$nz
    }
    return $map
}
# Every combination of three-colour order in two layers, with modal feedrates.
$source=[Collections.Generic.List[string]]::new()
@('; MANUAL_COLOUR_BOTTOM_LAYERS=2','; MANUAL_COLOUR_TOP_LAYERS=0','; MANUAL_COLOUR_EXPORT_CONFIRM=1','; extruder_colour = #000000;#FFFF00;#008000','G90','M83','G1 X0 Y0 Z0.2 F1000') | ForEach-Object {$source.Add($_)}
$loaded=0
foreach($l in 1..3){
    $source.Add(';LAYER_CHANGE');$source.Add(";Z:$($l*0.2)");$source.Add("G1 Z$($l*0.2) F720")
    $tools=if($l -eq 1){@(0,1,2)}elseif($l -eq 2){@(2,0,1)}else{@(2)}
    foreach($t in $tools){
        if($t -ne $loaded){$source.Add('; MANUAL_COLOUR_TOOLCHANGE');$source.Add('M600');$source.Add('G1 E0.3 F1500');$source.Add("T$t")}
        $loaded=$t
        $source.Add("G1 X$($t*10) Y$($l*10) F18000");$source.Add(';TYPE:Perimeter');$source.Add('G1 F1000')
        $source.Add("G1 X$($t*10+1) E0.1");$source.Add("G1 Y$($l*10+1) E0.2")
    }
}
$perms=@(@(0,1,2),@(0,2,1),@(1,0,2),@(1,2,0),@(2,0,1),@(2,1,0))
$expected=Get-Traces $source.ToArray();$count=0
foreach($a in $perms){foreach($b in $perms){
    $actual=Get-Traces (Reorder-FreeBottomLayers $source.ToArray() @{1=$a;2=$b} 2)
    foreach($key in $expected.Keys){if(($actual[$key] -join '|') -ne ($expected[$key] -join '|')){throw "Geometry/extrusion/feed mismatch $key for $a / $b"}}
    $count++
}}
Write-Host "PASS: $count two-layer permutations preserve every deposited segment, extrusion and feedrate"
$temp=Join-Path $env:TEMP ('free-reorder-validation-'+[guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory $temp)
$raw=Join-Path $temp 'source.gcode';[IO.File]::WriteAllLines($raw,$source.ToArray())
foreach($case in @('1:1,0,2;2:2,1,0','1:0,2,1;2:1,0,2','1:2,1,0;2:1,2,0')){
    $target=Join-Path $temp 'processed.gcode';Copy-Item $raw $target
    $env:MANUAL_COLOUR_TEST_ORDER=$case
    try{ & $processor $target }finally{Remove-Item Env:MANUAL_COLOUR_TEST_ORDER}
    $lines=[IO.File]::ReadAllLines($target);$actual=Get-Traces $lines
    foreach($key in $expected.Keys){if(($actual[$key] -join '|') -ne ($expected[$key] -join '|')){throw "FINAL output geometry/extrusion/feed mismatch $key for $case"}}
    if(@($lines | Where-Object {$_ -match '^T\d'}).Count){throw 'Virtual tool command leaked'}
    $a=@(($case.Split(';')[0].Split(':')[1]).Split(',') | ForEach-Object {[int]$_})
    $b=@(($case.Split(';')[1].Split(':')[1]).Split(',') | ForEach-Object {[int]$_})
    $labels=@('Black','Yellow','Green')
    if($lines -notcontains "; MANUAL_COLOUR_INITIAL=$($labels[$a[0]])"){throw 'Initial filament mismatch'}
    $pauses=4;if($a[-1] -ne $b[0]){$pauses++};if($b[-1] -ne 2){$pauses++}
    if(@($lines | Where-Object {$_ -match '^M600\b'}).Count -ne $pauses){throw 'Wrong final pause count'}
}
Write-Host "PASS: full writer, starting filament, M600 counts, no virtual T commands. UI fixture: $raw"
if($GcodePath){
    $source=[IO.File]::ReadAllLines($GcodePath);$expected=Get-Traces $source
    $orders=@{};foreach($l in 1..2){$orders[$l]=@($expected.Keys | Where-Object {$_ -like "$l/*"} | ForEach-Object {[int]($_ -split '/')[1]} | Sort-Object -Descending)}
    $actual=Get-Traces (Reorder-FreeBottomLayers $source $orders 2)
    foreach($key in $expected.Keys){if(($actual[$key] -join '|') -ne ($expected[$key] -join '|')){throw "Real-file geometry/extrusion/feed mismatch $key"}}
    Write-Host 'PASS: real sliced file preserves all bottom-layer deposited segments'
}
