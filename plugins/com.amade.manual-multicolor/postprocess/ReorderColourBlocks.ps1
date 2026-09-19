# Rebuild bottom-layer blocks with explicit entry coordinates and modal state.
# Only the checked single-nozzle, absolute-XYZ/relative-E workflow is supported.
function Reorder-FreeBottomLayers([string[]]$Source, [hashtable]$Orders, [int]$Bottom) {
    $starts = @(); $layer = 0; $tool = 0; $xyzAbsolute = $true; $relativeE = $true
    $x=$null; $y=$null; $z=$null; $feed=$null; $type=''; $width=''
    $modal=@{}; $blocks=@{}; $current=$null; $retracted=0.0
    for($i=0; $i -lt $Source.Count; $i++) {
        $line=$Source[$i]
        if($line -eq ';LAYER_CHANGE') {
            if($null -ne $current) { $current.End=$i-1; $current.EndRetraction=$retracted; $current=$null }
            $layer++; $starts += $i
            if($layer -eq 1){$startupRetraction=$retracted}
            if($layer -gt $Bottom) { break }
            $blocks[$layer]=[Collections.Generic.List[object]]::new()
            continue
        }
        if($line -eq '; MANUAL_COLOUR_TOOLCHANGE') {
            if($null -ne $current) { $current.End=$i-1; $current.EndRetraction=$retracted; $current=$null }
        }
        if($line -match '^T(\d+)(?:\s|$)') { $tool=[int]$Matches[1]; continue }
        if($line -match '^G90(?:\s|$)'){$xyzAbsolute=$true}
        if($line -match '^G91(?:\s|$)'){$xyzAbsolute=$false}
        if($line -match '^M83(?:\s|$)'){$relativeE=$true}
        if($line -match '^M82(?:\s|$)'){$relativeE=$false}
        if($layer -ge 1 -and (-not $xyzAbsolute -or -not $relativeE -or $line -match '^(G10|G11|G20)\b' -or $line -match '^G92\b.*\b[XYZ]')) { throw 'Free reorder requires absolute XYZ, relative E, millimetres and explicit retraction without XYZ coordinate resets within the bottom layers.' }
        if($line -match '^;TYPE:(.*)'){$type=$line}
        if($line -match '^;WIDTH:(.*)'){$width=$line}
        if($line -match '^(M104|M109|M106|M107|M142|M572|M201|M204|M205|M220|M221|M486)\b') {
            $key=$Matches[1]
            if($key -in @('M106','M107')){$key='fan'}
            if($key -in @('M104','M109')){$key='temperature'}
            if($key -eq 'M204') {
                foreach($axis in @('P','T','S')) { if($line -match "\b$axis([-+0-9.]+)") { $modal["M204$axis"]="M204 $axis$($Matches[1])" } }
            } else {$modal[$key]=$line}
        }
        if($line -notmatch '^G([0123])(?:\s|$)'){continue}
        $motion=[int]$Matches[1]
        $values=@{}
        foreach($match in [regex]::Matches(($line -split ';',2)[0], '(?:^|\s)([XYZEF])([-+]?(?:\d*\.)?\d+)')){$values[$match.Groups[1].Value]=[double]::Parse($match.Groups[2].Value,[Globalization.CultureInfo]::InvariantCulture)}
        if($layer -ge 1 -and $values.ContainsKey('E') -and $values.E -lt -5) { throw 'MMU unloading/ramming detected. Disable MMU loading/unloading and the wipe tower before free reordering.' }
        if($values.ContainsKey('F')){$feed=$values.F}
        $nx=if($values.ContainsKey('X')){$values.X}else{$x}
        $ny=if($values.ContainsKey('Y')){$values.Y}else{$y}
        $nz=if($values.ContainsKey('Z')){$values.Z}else{$z}
        $deposit=$layer -ge 1 -and $values.ContainsKey('E') -and $values.E -gt 0 -and ($motion -ge 2 -or $nx -ne $x -or $ny -ne $y)
        if($deposit -and $type -match 'Skirt|Brim|Support|Custom') { throw 'Free reorder does not support skirt, brim, support or custom extrusion blocks.' }
        if($deposit -and $null -eq $current) {
            if(-not $xyzAbsolute -or -not $relativeE -or $null -eq $x -or $null -eq $y -or $null -eq $z -or $null -eq $feed) { throw 'Free reorder requires known absolute XYZ and relative extrusion.' }
            if($type -match 'Skirt|Brim|Support|Custom') { throw 'Free reorder does not support skirt, brim, support or custom extrusion blocks.' }
            if(@($blocks[$layer] | Where-Object {$_.Tool -eq $tool}).Count){throw "Layer $layer repeats a tool block; free reorder is not supported for this file."}
            if($retracted -gt 0.001) { throw 'A model extrusion begins while retracted; this G-code cannot be safely reordered.' }
            $current=[pscustomobject]@{Tool=$tool;Start=$i;End=-1;EndRetraction=0.0;X=$x;Y=$y;Z=$z;Feed=$feed;Modal=$modal.Clone();Type=$type;Width=$width}
            $blocks[$layer].Add($current)
        }
        if($values.ContainsKey('E')){$retracted=[Math]::Max(0.0,$retracted-$values.E)}
        $x=$nx; $y=$ny; $z=$nz
    }
    if($starts.Count -le $Bottom){throw 'Free bottom reorder requires a following body layer.'}
    if([int]$Orders[1][0] -ne [int]$blocks[1][0].Tool){
        foreach($setting in @('first_layer_temperature','first_layer_bed_temperature','filament_type')){
            $config=@($Source | Where-Object {$_ -match "^; $setting = "})
            if($config.Count){
                $entries=($config[-1] -split ' = ',2)[1] -split ';'
                if($entries.Count -gt 1 -and $entries[[int]$Orders[1][0]] -ne $entries[[int]$blocks[1][0].Tool]){throw "Changing the starting filament requires matching $setting values; startup G-code has not been rewritten for mixed materials/temperatures."}
            }
        }
    }
    $result=[Collections.Generic.List[string]]::new()
    Add-GcodeRange $result $Source 0 ($starts[0]-1)
    if($startupRetraction -gt 0.001){$result.Add("G1 E$(Format-GcodeNumber $startupRetraction) F1500 ; normalize initial retraction")}
    $loaded=[int]$Orders[1][0]
    $result.Add("T$loaded ; virtual initial tool for reordered layers")
    for($l=1; $l -le $Bottom; $l++) {
        $row=@($blocks[$l].ToArray()); $order=@($Orders[$l])
        if((@($row.Tool | Sort-Object) -join ',') -ne (@($order | Sort-Object) -join ',')) { throw "Layer $l order does not match its actual model tool blocks." }
        if($row.Count -eq 0){throw "Layer $l contains no model toolpaths"}
        $result.Add(';LAYER_CHANGE')
        # Keep layer metadata outside the movable colour blocks.
        for($j=$starts[$l-1]+1; $j -lt $row[0].Start; $j++) {
            if($Source[$j] -match '^;(Z:|HEIGHT:|BEFORE_LAYER_CHANGE|AFTER_LAYER_CHANGE)'){$result.Add($Source[$j])}
        }
        $result.Add("; MANUAL_COLOUR_REORDERED_LAYER=$l : " + (($order | ForEach-Object { Get-ToolLabel $_ }) -join ' -> '))
        foreach($next in $order) {
            $block=@($row | Where-Object {$_.Tool -eq $next})[0]
            if($loaded -ne [int]$next) {
                if ($next -eq $order[0]) { $result.Add('; MANUAL_COLOUR_LAYER_ENTRY') }
                $result.Add('; MANUAL_COLOUR_TOOLCHANGE'); $result.Add('M600')
                $result.Add('G1 E0.3 F1500 ; prime after manual colour change'); $result.Add("T$next")
            }
            $loaded=[int]$next
            $result.Add("; MANUAL_COLOUR_BLOCK tool=$next layer=$l")
            foreach($key in @($block.Modal.Keys | Sort-Object)){$result.Add($block.Modal[$key])}
            if($block.Type){$result.Add($block.Type)}
            if($block.Width){$result.Add($block.Width)}
            $result.Add('G1 E-0.7 F2100 ; retract for reordered block entry')
            $result.Add("G1 Z$(Format-GcodeNumber ($block.Z + 0.6)) F720 ; safe block entry lift")
            $result.Add("G1 X$(Format-GcodeNumber $block.X) Y$(Format-GcodeNumber $block.Y) F18000 ; reordered block start")
            $result.Add("G1 Z$(Format-GcodeNumber $block.Z) F720")
            $result.Add('G1 E0.7 F1500 ; restore retraction')
            $result.Add("G1 F$(Format-GcodeNumber $block.Feed)")
            Add-GcodeRange $result $Source $block.Start $block.End
            if($block.EndRetraction -gt 0.001){$result.Add("G1 E$(Format-GcodeNumber $block.EndRetraction) F1500 ; normalize outgoing block retraction")}
        }
    }
    # Restore the original boundary state before the untouched body. Its first
    # moves may omit modal coordinates/feed or expect an existing retraction.
    $result.Add('G1 E-0.7 F2100 ; retract for body boundary')
    $result.Add("G1 Z$(Format-GcodeNumber ($z+0.6)) F720")
    $result.Add("G1 X$(Format-GcodeNumber $x) Y$(Format-GcodeNumber $y) F18000")
    $result.Add("G1 Z$(Format-GcodeNumber $z) F720")
    $result.Add('G1 E0.7 F1500 ; restore retraction')
    if($retracted -gt 0.001){$result.Add("G1 E-$(Format-GcodeNumber $retracted) F2100 ; restore original body entry retraction")}
    foreach($key in @($modal.Keys | Sort-Object)){$result.Add($modal[$key])}
    if($type){$result.Add($type)}
    if($width){$result.Add($width)}
    $result.Add("G1 F$(Format-GcodeNumber $feed)")
    Add-GcodeRange $result $Source $starts[$Bottom] ($Source.Count-1)
    return $result.ToArray()
}
