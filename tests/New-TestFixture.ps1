param([Parameter(Mandatory=$true)][string]$Destination)
# Synthetic geometry for software checks only. No homing/heating; never print.
$lines = [Collections.Generic.List[string]]::new()
@('; SYNTHETIC TEST FIXTURE - DO NOT PRINT',
  '; MANUAL_COLOUR_BOTTOM_LAYERS=2','; MANUAL_COLOUR_TOP_LAYERS=2',
  '; MANUAL_COLOUR_EXPORT_CONFIRM=1',
  '; extruder_colour = #000000;#FFFF00;#008000',
  'G90','M83','G1 X0 Y0 Z0.2 F1000') | ForEach-Object { $lines.Add($_) }
$loaded = 0
foreach ($layer in 1..22) {
    $z = ($layer * 0.2).ToString('0.00',[Globalization.CultureInfo]::InvariantCulture)
    $lines.Add(';LAYER_CHANGE'); $lines.Add(";Z:$z"); $lines.Add("G1 Z$z F720")
    $order = if ($layer -eq 1) { @(0,1,2) } elseif ($layer -eq 2) { @(2,0,1) } else { @(2) }
    foreach ($tool in $order) {
        if ($tool -ne $loaded) {
            @('; MANUAL_COLOUR_TOOLCHANGE','M600','G1 E0.3 F1500',"T$tool") | ForEach-Object { $lines.Add($_) }
        }
        $loaded = $tool
        $lines.Add("G1 X$($tool*10) Y$($layer*10) F18000")
        $lines.Add(';TYPE:Perimeter'); $lines.Add('G1 F1000')
        $lines.Add("G1 X$($tool*10+1) E0.1"); $lines.Add("G1 Y$($layer*10+1) E0.2")
    }
}
$lines.Add('; prusaslicer_config = end')
[IO.File]::WriteAllLines($Destination,$lines.ToArray(),[Text.UTF8Encoding]::new($false))
