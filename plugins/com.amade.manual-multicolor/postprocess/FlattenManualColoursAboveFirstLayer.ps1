<#
Keeps stock M600 changes on layer 1, then switches once to the base colour and
removes all later manual virtual-tool-change blocks.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string] $GcodePath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $GcodePath -PathType Leaf)) {
    throw "G-code file not found: $GcodePath"
}

$lines = [System.IO.File]::ReadAllLines($GcodePath)
$bottomColourLayers = 1
$topColourLayers = 0
$confirmExport = $true
$labels = @()
$selectedColours = @()
$requestedBaseSlot = $null
foreach ($configLine in $lines) {
    if ($configLine -match '^; MANUAL_COLOUR_BASE_SLOT=(\d+)\s*$') { $requestedBaseSlot = [int]$Matches[1] }
    if ($configLine -match '^; MANUAL_COLOUR_BOTTOM_LAYERS=(0|1|2)\s*$') {
        $bottomColourLayers = [int] $Matches[1]
    }
    # Backward compatibility with the former bottom-layer directive.
    if ($configLine -match '^; MANUAL_COLOUR_LAYERS=(1|2)\s*$') {
        $bottomColourLayers = [int] $Matches[1]
    }
    if ($configLine -match '^; MANUAL_COLOUR_TOP_LAYERS=(0|1|2)\s*$') {
        $topColourLayers = [int] $Matches[1]
    }
    if ($configLine -match '^; MANUAL_COLOUR_EXPORT_CONFIRM=(0|1)\s*$') {
        $confirmExport = $Matches[1] -eq '1'
    }
    if ($configLine -match '^; MANUAL_COLOUR_LABELS=(.+)$') {
        $labels = @($Matches[1].Split(',') | ForEach-Object { $_.Trim() })
    }
    if ($configLine -match '^; extruder_colour = (.+)$') {
        $selectedColours = @($Matches[1].Split(';') | ForEach-Object { $_.Trim() })
    }
}

function Get-ColourName([string] $Colour) {
    switch ($Colour.ToUpperInvariant()) {
        '#000000' { return 'Black' }
        '#FFFFFF' { return 'White' }
        '#FF0000' { return 'Red' }
        '#00FF00' { return 'Lime' }
        '#008000' { return 'Green' }
        '#0000FF' { return 'Blue' }
        '#FFFF00' { return 'Yellow' }
        '#FFA500' { return 'Orange' }
        '#FF8000' { return 'Orange' }
        '#800080' { return 'Purple' }
        '#FFC0CB' { return 'Pink' }
        '#808080' { return 'Grey' }
        '#A52A2A' { return 'Brown' }
        default {
            if ($Colour -notmatch '^#[0-9A-Fa-f]{6}$') { return $Colour }
            Add-Type -AssemblyName System.Drawing
            $rgb = [Drawing.ColorTranslator]::FromHtml($Colour)
            $max = [Math]::Max($rgb.R, [Math]::Max($rgb.G, $rgb.B))
            $min = [Math]::Min($rgb.R, [Math]::Min($rgb.G, $rgb.B))
            if ($max -lt 45) { return 'Black' }
            if ($min -gt 225) { return 'White' }
            if (($max - $min) -lt 25) { return 'Grey' }
            $hue = $rgb.GetHue()
            if ($hue -lt 15 -or $hue -ge 345) { return 'Red' }
            if ($hue -lt 45) {
                if ($rgb.GetBrightness() -lt 0.45) { return 'Brown' }
                return 'Orange'
            }
            if ($hue -lt 70) { return 'Yellow' }
            if ($hue -lt 165) { return 'Green' }
            if ($hue -lt 195) { return 'Cyan' }
            if ($hue -lt 265) { return 'Blue' }
            if ($hue -lt 295) { return 'Purple' }
            return 'Pink'
        }
    }
}

function Get-ToolLabel([int] $Tool) {
    # Explicit slot names override automatic colour-family naming.
    if ($Tool -ge 0 -and $Tool -lt $labels.Count -and -not [string]::IsNullOrWhiteSpace($labels[$Tool])) {
        return $labels[$Tool]
    }
    if ($Tool -ge 0 -and $Tool -lt $selectedColours.Count -and $selectedColours[$Tool] -match '^#[0-9A-Fa-f]{6}$') {
        return Get-ColourName $selectedColours[$Tool]
    }
    if ($Tool -ge 0 -and $Tool -lt $labels.Count -and -not [string]::IsNullOrWhiteSpace($labels[$Tool])) {
        return $labels[$Tool]
    }
    return "Tool $($Tool + 1)"
}

function Get-ToolDisplayColour([int] $Tool) {
    if ($Tool -ge 0 -and $Tool -lt $selectedColours.Count -and $selectedColours[$Tool] -match '^#[0-9A-Fa-f]{6}$') {
        return [System.Drawing.ColorTranslator]::FromHtml($selectedColours[$Tool])
    }
    return [System.Drawing.Color]::SlateGray
}

function Get-ToolHexColour([int] $Tool) {
    if ($Tool -ge 0 -and $Tool -lt $selectedColours.Count -and $selectedColours[$Tool] -match '^#[0-9A-Fa-f]{6}$') {
        return $selectedColours[$Tool].ToUpperInvariant()
    }
    switch ((Get-ToolLabel $Tool).ToUpperInvariant()) {
        'BLACK'  { return '#000000' }
        'WHITE'  { return '#FFFFFF' }
        'RED'    { return '#FF0000' }
        'GREEN'  { return '#008000' }
        'LIME'   { return '#00FF00' }
        'BLUE'   { return '#0000FF' }
        'YELLOW' { return '#FFFF00' }
        'ORANGE' { return '#FFA500' }
        'PURPLE' { return '#800080' }
        'PINK'   { return '#FFC0CB' }
        'GREY'   { return '#808080' }
        'GRAY'   { return '#808080' }
        'BROWN'  { return '#A52A2A' }
        default  { return '#808080' }
    }
}

function Get-M600ColourText([string] $Label) {
    # Buddy firmware's named colour parser is case-sensitive. Use its preset
    # spelling (WHITE, BLUE, BLACK, etc.) so M600 shows the colour on screen.
    $text = $Label.Replace('"', '').Trim()
    if ($text.Length -gt 20) { $text = $text.Substring(0, 20) }
    switch ($text.ToUpperInvariant()) {
        'GREY' { return 'GRAY' }
        default { return $text.ToUpperInvariant() }
    }
}

function Format-GcodeNumber([double] $Value) {
    return $Value.ToString('0.###', [System.Globalization.CultureInfo]::InvariantCulture)
}

function Get-ColourLayerToolpaths([string[]] $SourceLines, [int] $BottomLayers, [int] $TopLayers, [int] $TotalLayers) {
    # A lightweight preview reader: records XY extrusion moves and their
    # virtual tool before the final G-code removes T commands.
    $paths = [System.Collections.Generic.List[object]]::new()
    $layer = 0; $tool = 0; $x = $null; $y = $null; $lastE = 0.0; $relativeE = $true; $currentType = ''
    $sourceIndex = -1
    foreach ($sourceLine in $SourceLines) {
        $sourceIndex++
        if ($sourceLine -match '^;LAYER_CHANGE\s*$') { $layer++; continue }
        if ($sourceLine -match '^;TYPE:(.+)$') { $currentType = $Matches[1].Trim(); continue }
        if ($sourceLine -match '^M82(?:\s|$)') { $relativeE = $false; continue }
        if ($sourceLine -match '^M83(?:\s|$)') { $relativeE = $true; continue }
        if ($sourceLine -match '^\s*T(\d+)(?:\s*;.*)?$') { $tool = [int]$Matches[1]; continue }
        if ($sourceLine -match '^G92\s+.*\bE(-?[0-9.]+)') { $lastE = [double]$Matches[1]; continue }
        if ($sourceLine -notmatch '^G[01](?:\s|$)') { continue }
        $matchX = [regex]::Match($sourceLine, '(?:^|\s)X(-?[0-9.]+)')
        $matchY = [regex]::Match($sourceLine, '(?:^|\s)Y(-?[0-9.]+)')
        $matchE = [regex]::Match($sourceLine, '(?:^|\s)E(-?[0-9.]+)')
        $newX = if ($matchX.Success) { [double]$matchX.Groups[1].Value } else { $x }
        $newY = if ($matchY.Success) { [double]$matchY.Groups[1].Value } else { $y }
        if ($matchE.Success) {
            $e = [double]$matchE.Groups[1].Value
            $extruding = if ($relativeE) { $e -gt 0 } else { $e -gt $lastE + 0.00001 }
            $isBottom = $layer -ge 1 -and $layer -le $BottomLayers
            $isTop = $TopLayers -gt 0 -and $layer -gt ($TotalLayers - $TopLayers)
            $isModelExtrusion = $currentType -notmatch '^(Skirt/Brim|Custom)$'
            if ($extruding -and $isModelExtrusion -and ($isBottom -or $isTop) -and $null -ne $x -and $null -ne $y -and $null -ne $newX -and $null -ne $newY) {
                $paths.Add([pscustomobject]@{ Layer = $layer; Tool = $tool; X1 = $x; Y1 = $y; X2 = $newX; Y2 = $newY; SourceIndex = $sourceIndex })
            }
            if (-not $relativeE) { $lastE = $e }
        }
        $x = $newX; $y = $newY
    }
    return $paths
}

function Add-GcodeRange([System.Collections.Generic.List[string]] $Target, [string[]] $Source, [int] $Start, [int] $End) {
    if ($Start -gt $End) { return }
    for ($rangeIndex = $Start; $rangeIndex -le $End; $rangeIndex++) { $Target.Add($Source[$rangeIndex]) }
}

function Reorder-ManualColourLayerBlocks([string[]] $SourceLines, [hashtable] $DesiredSequences) {
    # PrusaSlicer emits each virtual-colour section as: geometry for the
    # current tool, then MANUAL_COLOUR_TOOLCHANGE and the next T<n> section.
    # Move complete sections, rather than merely changing M600 labels, so the
    # geometry and the filament always remain paired.
    $layerStarts = [System.Collections.Generic.List[int]]::new()
    for ($sourceIndex = 0; $sourceIndex -lt $SourceLines.Count; $sourceIndex++) {
        if ($SourceLines[$sourceIndex] -match '^;LAYER_CHANGE\s*$') { $layerStarts.Add($sourceIndex) }
    }
    if ($layerStarts.Count -eq 0) { return $SourceLines }
    $rebuilt = [System.Collections.Generic.List[string]]::new()
    $cursor = 0; $activeTool = 0
    for ($layerNumber = 1; $layerNumber -le $layerStarts.Count; $layerNumber++) {
        $layerStart = $layerStarts[$layerNumber - 1]
        $layerEnd = if ($layerNumber -lt $layerStarts.Count) { $layerStarts[$layerNumber] - 1 } else { $SourceLines.Count - 1 }
        Add-GcodeRange $rebuilt $SourceLines $cursor $layerStart
        $markerIndexes = [System.Collections.Generic.List[int]]::new()
        for ($insideIndex = $layerStart + 1; $insideIndex -le $layerEnd; $insideIndex++) {
            if ($SourceLines[$insideIndex] -eq '; MANUAL_COLOUR_TOOLCHANGE') { $markerIndexes.Add($insideIndex) }
        }
        $originalTools = [System.Collections.Generic.List[int]]::new()
        $originalTools.Add($activeTool)
        $incomingTools = [System.Collections.Generic.List[int]]::new()
        foreach ($markerIndex in $markerIndexes) {
            $incomingTool = $null
            for ($toolIndex = $markerIndex + 1; $toolIndex -le [Math]::Min($layerEnd, $markerIndex + 80); $toolIndex++) {
                if ($SourceLines[$toolIndex] -match '^\s*T(\d+)(?:\s*;.*)?$') { $incomingTool = [int]$Matches[1]; break }
            }
            if ($null -eq $incomingTool) { break }
            $incomingTools.Add([int]$incomingTool)
            $originalTools.Add([int]$incomingTool)
        }
        [int[]]$desiredTools = if ($DesiredSequences.ContainsKey($layerNumber)) { @($DesiredSequences[$layerNumber]) } else { @($originalTools) }
        $uniqueOriginalCount = (@($originalTools | Select-Object -Unique)).Count
        $canReorder = $markerIndexes.Count -gt 0 -and $incomingTools.Count -eq $markerIndexes.Count -and $desiredTools.Count -eq $originalTools.Count -and $desiredTools[0] -eq $originalTools[0] -and (@($desiredTools | Sort-Object) -join ',') -eq (@($originalTools | Sort-Object) -join ',') -and $uniqueOriginalCount -eq $originalTools.Count
        if ($canReorder -and (@($desiredTools) -join ',') -ne (@($originalTools) -join ',')) {
            # First section has no incoming M600; it is fixed to the filament
            # that was already loaded at the start of this layer.  All later
            # marker-to-marker sections can be moved safely as whole blocks.
            Add-GcodeRange $rebuilt $SourceLines ($layerStart + 1) ($markerIndexes[0] - 1)
            $toolToChunk = @{}
            for ($chunk = 0; $chunk -lt $markerIndexes.Count; $chunk++) {
                $chunkEnd = if ($chunk + 1 -lt $markerIndexes.Count) { $markerIndexes[$chunk + 1] - 1 } else { $layerEnd }
                $toolToChunk[[int]$incomingTools[$chunk]] = [pscustomobject]@{ Start = $markerIndexes[$chunk]; End = $chunkEnd }
            }
            $rebuilt.Add("; MANUAL_COLOUR_REORDERED_LAYER=$layerNumber : " + (@($desiredTools | ForEach-Object { Get-ToolLabel $_ }) -join ' -> '))
            for ($desiredIndex = 1; $desiredIndex -lt $desiredTools.Count; $desiredIndex++) {
                $chunkRange = $toolToChunk[[int]$desiredTools[$desiredIndex]]
                Add-GcodeRange $rebuilt $SourceLines $chunkRange.Start $chunkRange.End
            }
        } else {
            Add-GcodeRange $rebuilt $SourceLines ($layerStart + 1) $layerEnd
        }
        if ($incomingTools.Count -gt 0) { $activeTool = [int]$incomingTools[$incomingTools.Count - 1] }
        $cursor = $layerEnd + 1
    }
    Add-GcodeRange $rebuilt $SourceLines $cursor ($SourceLines.Count - 1)
    return $rebuilt.ToArray()
}

$output = [System.Collections.Generic.List[string]]::new()
$layerCount = 0
$totalLayerCount = @($lines | Where-Object { $_ -match '^;LAYER_CHANGE\s*$' }).Count
# Moving model extrusion determines the body colour, not slot order.
$allModelPaths = @(Get-ColourLayerToolpaths $lines $totalLayerCount 0 $totalLayerCount | Where-Object {
    [Math]::Abs($_.X2 - $_.X1) + [Math]::Abs($_.Y2 - $_.Y1) -gt 0.00001
})
$middleTools = @($allModelPaths | Where-Object { $_.Layer -gt $bottomColourLayers -and $_.Layer -le ($totalLayerCount - $topColourLayers) } | Select-Object -ExpandProperty Tool -Unique)
if ($null -ne $requestedBaseSlot) {
    if ($requestedBaseSlot -lt 1 -or $requestedBaseSlot -gt $selectedColours.Count) { throw 'MANUAL_COLOUR_BASE_SLOT must name an existing filament slot (1-based).' }
    $baseTool = $requestedBaseSlot - 1
} elseif ($middleTools.Count -eq 1) {
    $baseTool = [int]$middleTools[0]
} else {
    throw 'Cannot infer one body colour from middle-layer extrusion. Set ; MANUAL_COLOUR_BASE_SLOT=3 (or the correct 1-based slot) in Start G-code and re-export.'
}
$requestedTopLayers = $topColourLayers
$topPaths = @($allModelPaths | Where-Object { $_.Layer -gt ($totalLayerCount - $topColourLayers) })
if ($topColourLayers -gt 0 -and $topPaths.Count -gt 0 -and @($topPaths | Where-Object { $_.Tool -ne $baseTool }).Count -eq 0) { $topColourLayers = 0 }
$layerHeights = @{}
$heightLayer = 0
foreach ($heightLine in $lines) {
    if ($heightLine -match '^;LAYER_CHANGE\s*$') { $heightLayer++; continue }
    if ($heightLine -match '^;Z:([-+]?[0-9]*\.?[0-9]+)\s*$') { $layerHeights[$heightLayer] = [double]$Matches[1] }
}
$colourSummary = if ($selectedColours.Count -gt 0) {
    @(for ($tool = 0; $tool -lt $selectedColours.Count; $tool++) { "T$($tool + 1) = $(Get-ToolLabel $tool)" }) -join ', '
} else { 'Colours will be taken from the active virtual extruders.' }

# Build the exact M600 plan from the sliced virtual-tool markers before the
# post-processor removes any middle-layer changes. This is shown to the user
# before writing the final G-code.
$plannedChanges = @{}
$plannedEvents = [System.Collections.Generic.List[object]]::new()
$layerStartIndices = @{}
$scanLayer = 0
for ($scanIndex = 0; $scanIndex -lt $lines.Count; $scanIndex++) {
    if ($lines[$scanIndex] -match '^;LAYER_CHANGE\s*$') {
        $scanLayer++
        $layerStartIndices[$scanLayer] = $scanIndex
        continue
    }
    $scanBottom = $scanLayer -ge 1 -and $scanLayer -le $bottomColourLayers
    $scanTop = $topColourLayers -gt 0 -and $scanLayer -gt ($totalLayerCount - $topColourLayers)
    if (($scanBottom -or $scanTop) -and $lines[$scanIndex] -eq '; MANUAL_COLOUR_TOOLCHANGE') {
        $tool = 0
        if ($scanIndex + 3 -lt $lines.Count -and $lines[$scanIndex + 3] -match '^\s*T(\d+)(?:\s*;.*)?$') {
            $tool = [int] $Matches[1]
        }
        if (-not $plannedChanges.ContainsKey($scanLayer)) {
            $plannedChanges[$scanLayer] = [System.Collections.Generic.List[string]]::new()
        }
        $label = Get-ToolLabel $tool
        $plannedChanges[$scanLayer].Add($label)
        $plannedEvents.Add([pscustomobject]@{ Layer = $scanLayer; Label = $label; Tool = $tool; SourceIndex = $scanIndex })
    }
}

# After the last bottom-colour layer, the script inserts one base-colour M600
# only when the selected bottom section actually ends on a non-base colour.
$baseReturnLayer = $bottomColourLayers + 1
$bottomEvents = @($plannedEvents | Where-Object { $_.Layer -ge 1 -and $_.Layer -le $bottomColourLayers } | Sort-Object SourceIndex)
$lastBottomTool = if ($bottomEvents.Count -gt 0) { [int]$bottomEvents[$bottomEvents.Count - 1].Tool } else { 0 }
$baseReturnIsNeeded = $bottomColourLayers -gt 0 -and $lastBottomTool -ne $baseTool -and $baseReturnLayer -le $totalLayerCount -and -not ($topColourLayers -gt 0 -and $baseReturnLayer -gt ($totalLayerCount - $topColourLayers))
if ($baseReturnIsNeeded) {
    if (-not $plannedChanges.ContainsKey($baseReturnLayer)) {
        $plannedChanges[$baseReturnLayer] = [System.Collections.Generic.List[string]]::new()
    }
    $baseLabel = "$(Get-ToolLabel $baseTool) (return to base)"
    $plannedChanges[$baseReturnLayer].Insert(0, $baseLabel)
    $plannedEvents.Add([pscustomobject]@{ Layer = $baseReturnLayer; Label = $baseLabel; Tool = $baseTool; SourceIndex = $layerStartIndices[$baseReturnLayer] })
}
$plannedPauseCount = @($plannedChanges.Values | ForEach-Object { $_.Count } | Measure-Object -Sum).Sum
$initialColour = Get-ToolLabel 0
$activePreviewTool = 0
$sequenceLines = [System.Collections.Generic.List[string]]::new()
$layerStartTools = @{}
$layerEndTools = @{}
$layerSequenceTools = @{}
for ($previewLayer = 1; $previewLayer -le $totalLayerCount; $previewLayer++) {
    if ($previewLayer -eq $baseReturnLayer) { $activePreviewTool = $baseTool }
    $layerStartTools[$previewLayer] = $activePreviewTool
    $previewBottom = $previewLayer -le $bottomColourLayers
    $previewTop = $topColourLayers -gt 0 -and $previewLayer -gt ($totalLayerCount - $topColourLayers)
    if (-not ($previewBottom -or $previewTop)) {
        $layerSequenceTools[$previewLayer] = @([int]$activePreviewTool)
        $layerEndTools[$previewLayer] = $activePreviewTool
        continue
    }
    $sequenceTools = [System.Collections.Generic.List[int]]::new()
    $sequenceTools.Add([int]$activePreviewTool)
    $layerEvents = @($plannedEvents | Where-Object { $_.Layer -eq $previewLayer } | Sort-Object SourceIndex)
    foreach ($layerEvent in $layerEvents) {
        if ([int]$layerEvent.Tool -ne $activePreviewTool) {
            $activePreviewTool = [int]$layerEvent.Tool
            $sequenceTools.Add([int]$activePreviewTool)
        }
    }
    $layerSequenceTools[$previewLayer] = $sequenceTools.ToArray()
    $layerEndTools[$previewLayer] = $activePreviewTool
    $sequenceLines.Add("Layer ${previewLayer}: " + (@($sequenceTools | ForEach-Object { Get-ToolLabel $_ }) -join ' -> '))
}
$maxPreviewColours = [Math]::Max(1, [int](($layerSequenceTools.Values | ForEach-Object { @($_).Count } | Measure-Object -Maximum).Maximum))
$originalBottomOrders = @{}
for ($originalLayer=1; $originalLayer -le $bottomColourLayers; $originalLayer++) { $originalBottomOrders[$originalLayer] = @($layerSequenceTools[$originalLayer]) }
# Default to finishing the bottom section with its detected body material.
# Preserve tool membership and the initial filament; only swap whole blocks.
if ($bottomColourLayers -ge 2 -and $bottomColourLayers -lt ($totalLayerCount - $topColourLayers)) {
    $autoRow = [int[]]@($layerSequenceTools[$bottomColourLayers])
    $autoBaseIndex = [array]::IndexOf($autoRow, [int]$baseTool)
    if ($autoBaseIndex -ge 0 -and $autoBaseIndex -ne ($autoRow.Count - 1)) {
        $autoRow[$autoBaseIndex] = $autoRow[-1]
        $autoRow[-1] = [int]$baseTool
        $layerSequenceTools[$bottomColourLayers] = $autoRow
        # Match adjacent rows where possible without changing their first tool.
        for ($autoLayer=$bottomColourLayers-1; $autoLayer -ge 1; $autoLayer--) {
            $priorRow = [int[]]@($layerSequenceTools[$autoLayer])
            $wanted = [int]$layerSequenceTools[$autoLayer+1][0]
            $wantedIndex = [array]::IndexOf($priorRow, $wanted)
            if ($wantedIndex -gt 0 -and $wantedIndex -ne ($priorRow.Count-1)) {
                $priorRow[$wantedIndex]=$priorRow[-1]; $priorRow[-1]=$wanted
                $layerSequenceTools[$autoLayer]=$priorRow
            }
        }
    }
}
$sequenceLines.Clear()
$plannedPauseCount=0; $autoActive=[int]$layerSequenceTools[1][0]
for ($autoLayer=1; $autoLayer -le $totalLayerCount; $autoLayer++) {
    foreach ($autoTool in @($layerSequenceTools[$autoLayer])) {
        if ([int]$autoTool -ne $autoActive) { $plannedPauseCount++; $autoActive=[int]$autoTool }
    }
    if ($autoLayer -le $bottomColourLayers -or ($topColourLayers -gt 0 -and $autoLayer -gt ($totalLayerCount-$topColourLayers))) {
        $sequenceLines.Add("Layer ${autoLayer}: " + (@($layerSequenceTools[$autoLayer] | ForEach-Object { Get-ToolLabel $_ }) -join ' -> '))
    }
}
$plannedSchedule = "Start: $initialColour (initial filament; no pause)" + "`n" + ($sequenceLines -join "`n")

# Internal non-interactive regression hook. It is inactive during normal
# PrusaSlicer exports and lets the full writer be tested without showing UI.
if (-not [string]::IsNullOrWhiteSpace($env:MANUAL_COLOUR_TEST_ORDER)) {
    $confirmExport = $false
    foreach ($testOrder in $env:MANUAL_COLOUR_TEST_ORDER.Split(';')) {
        if ($testOrder -match '^(\d+):([0-9,]+)$') {
            $testLayer = [int]$Matches[1]
            $layerSequenceTools[$testLayer] = @($Matches[2].Split(',') | ForEach-Object { [int]$_ })
        }
    }
}

if ($confirmExport) {
    $previewTracePath = Join-Path $env:LOCALAPPDATA 'PrusaManualMulticolor\preview.log'
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($previewTracePath))
    [IO.File]::AppendAllText($previewTracePath, "$(Get-Date -Format o) PID=$PID Preparing preview for $GcodePath`r`n")
    $colourLayerToolpaths = Get-ColourLayerToolpaths $lines $bottomColourLayers $topColourLayers $totalLayerCount
    $message = @"
EXPORT SUMMARY

Bottom colour layers: $bottomColourLayers
Top colour layers:    $topColourLayers
Total sliced layers:  $totalLayerCount
Planned manual pauses: $plannedPauseCount
Initial filament: $initialColour
Body/base: slot $($baseTool + 1) - $(Get-ToolLabel $baseTool)

Middle layers print in the body/base colour.

COLOUR ORDER
$plannedSchedule

FILAMENT SLOTS
$($colourSummary -replace ', ', "`r`n")

Continue and write this G-code?
"@
    try {
        Add-Type -AssemblyName System.Windows.Forms
        Add-Type -AssemblyName System.Drawing
        # GetNewClosure creates a module scope that cannot resolve script-local
        # helper functions when launched by the watcher. Capture values instead.
        $previewToolColours = @{}
        $previewToolLabels = @{}
        $previewTools = @(0) + @($layerSequenceTools.Values | ForEach-Object { $_ }) + @($colourLayerToolpaths | ForEach-Object { $_.Tool })
        foreach ($previewTool in ($previewTools | Sort-Object -Unique)) {
            $previewToolColours[[int]$previewTool] = Get-ToolDisplayColour ([int]$previewTool)
            $previewToolLabels[[int]$previewTool] = Get-ToolLabel ([int]$previewTool)
        }
        $preview = [System.Windows.Forms.Form]::new()
        [IO.File]::AppendAllText($previewTracePath, "PID=$PID Form created`r`n")
        $preview.Text = 'Manual Colours - export preview'
        $preview.Size = [System.Drawing.Size]::new(1320, 760)
        $preview.MinimumSize = [System.Drawing.Size]::new(1040, 640)
        $preview.StartPosition = 'CenterScreen'
        $preview.Font = [System.Drawing.Font]::new('Segoe UI', 9)
        $preview.MinimizeBox = $true
        $preview.MaximizeBox = $true

        $heading = [System.Windows.Forms.Label]::new()
        $heading.Text = "Bottom: $bottomColourLayers layer(s)     Top: $topColourLayers layer(s)     Manual pauses: $plannedPauseCount"
        $heading.Location = [System.Drawing.Point]::new(18, 16)
        $heading.Size = [System.Drawing.Size]::new(1070, 24)
        $heading.Font = [System.Drawing.Font]::new('Segoe UI Semibold', 10)

        $hint = [System.Windows.Forms.Label]::new()
        $hint.Text = 'Click a colour to view its paths. Drag any bottom-layer colour onto another cell in the same row to swap print order. Check the initial filament before printing.'
        $hint.Location = [System.Drawing.Point]::new(18, 44)
        $hint.Size = [System.Drawing.Size]::new(1070, 22)

        $bar = [System.Windows.Forms.Panel]::new()
        $bar.Location = [System.Drawing.Point]::new(18, 74)
        $bar.Size = [System.Drawing.Size]::new(140, 470)
        $bar.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
        $bar.Tag = [pscustomobject]@{ Layer = 1; Tool = $null }
        $totalForBar = [Math]::Max($totalLayerCount, 1)
        $bar.Add_Paint({
            param($sender, $paint)
            # Once the real cell controls are built, they are the complete UI.
            # Do not draw a second painted grid underneath them.
            if ($sender.Controls.Count -gt 0) { return }
            $graphics = $paint.Graphics
            $left = 10; $top = 24; $width = $sender.ClientSize.Width - 20; $height = $sender.ClientSize.Height - 36
            $labelWidth = 42; $cellsLeft = $left + $labelWidth; $cellsWidth = $width - $labelWidth
            $rowHeight = $height / [double]$totalForBar
            $graphics.DrawString("PRINTING ORDER  ->  (up to $maxPreviewColours colours)", $sender.Font, [System.Drawing.Brushes]::DimGray, $cellsLeft, 3)
            for ($displayLayer = 1; $displayLayer -le $totalForBar; $displayLayer++) {
                $rowY = $top + [int](($totalForBar - $displayLayer) * $rowHeight)
                $rowBottom = $top + [int](($totalForBar - $displayLayer + 1) * $rowHeight)
                $rowPixels = [Math]::Max(1, $rowBottom - $rowY)
                $sequenceTools = @($layerSequenceTools[$displayLayer])
                $cellCount = [Math]::Max(1, $sequenceTools.Count)
                $graphics.FillRectangle([System.Drawing.Brushes]::Gainsboro, $left, $rowY, $labelWidth, $rowPixels)
                for ($cellIndex = 0; $cellIndex -lt $cellCount; $cellIndex++) {
                    $cellLeft = $cellsLeft + [int]($cellsWidth * $cellIndex / $cellCount)
                    $cellRight = $cellsLeft + [int]($cellsWidth * ($cellIndex + 1) / $cellCount)
                    $brush = [System.Drawing.SolidBrush]::new($previewToolColours[[int]$sequenceTools[$cellIndex]])
                    $graphics.FillRectangle($brush, $cellLeft, $rowY, [Math]::Max(1, $cellRight - $cellLeft), $rowPixels)
                    $brush.Dispose()
                    # This border is the exact clickable box; no decorative
                    # grid is allowed to cut through a different hit region.
                    $graphics.DrawRectangle([System.Drawing.Pens]::DimGray, $cellLeft, $rowY, [Math]::Max(1, $cellRight - $cellLeft), [Math]::Max(1, $rowPixels - 1))
                }
                $graphics.DrawRectangle([System.Drawing.Pens]::DimGray, $left, $rowY, $width, $rowPixels)
                if ($rowPixels -ge 16) { $graphics.DrawString("L $displayLayer", $sender.Font, [System.Drawing.Brushes]::Black, $left + 3, $rowY) }
            }
            $selectedLayer = [int]$sender.Tag.Layer
            $selectedY = $top + [int](($totalForBar - $selectedLayer) * $rowHeight)
            $selectedBottom = $top + [int](($totalForBar - $selectedLayer + 1) * $rowHeight)
            $selectedSequence = @($layerSequenceTools[$selectedLayer])
            $selectionLeft = $cellsLeft; $selectionWidth = $cellsWidth
            if ($null -ne $sender.Tag.Tool -and $selectedSequence.Count -gt 1) {
                $selectedIndex = [array]::IndexOf([int[]]$selectedSequence, [int]$sender.Tag.Tool)
                if ($selectedIndex -ge 0) {
                    $selectionLeft = $cellsLeft + [int]($cellsWidth * $selectedIndex / $selectedSequence.Count)
                    $selectionRight = $cellsLeft + [int]($cellsWidth * ($selectedIndex + 1) / $selectedSequence.Count)
                    $selectionWidth = [Math]::Max(1, $selectionRight - $selectionLeft)
                }
            }
            $selectionPen = [System.Drawing.Pen]::new([System.Drawing.Color]::DarkOrange, 3)
            $graphics.DrawRectangle($selectionPen, $selectionLeft - 1, $selectedY - 1, $selectionWidth + 2, [Math]::Max(2, $selectedBottom - $selectedY))
            $selectionPen.Dispose()
        }.GetNewClosure())

        $scheduleBox = [System.Windows.Forms.TextBox]::new()
        $scheduleBox.Location = [System.Drawing.Point]::new(178, 74)
        $scheduleBox.Size = [System.Drawing.Size]::new(360, 470)
        $scheduleBox.Multiline = $true
        $scheduleBox.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical
        $scheduleBox.ReadOnly = $true
        $scheduleBox.Font = [System.Drawing.Font]::new('Segoe UI', 10)
        $scheduleBox.WordWrap = $true
        # Native multiline TextBox requires CRLF, including here-string text
        # from LF-only script files. Bare LF previously concatenated the lines.
        $scheduleBox.Text = [regex]::Replace($message, '\r\n|\r|\n', "`r`n")
        $scheduleBox.SelectionStart = 0
        $scheduleBox.SelectionLength = 0

        $sliceLabel = [System.Windows.Forms.Label]::new()
        $sliceLabel.Text = 'Colour-layer material (drag the height bar; middle single-colour layers are ignored)'
        $sliceLabel.Location = [System.Drawing.Point]::new(558, 74)
        $sliceLabel.Size = [System.Drawing.Size]::new(540, 20)
        $sliceLayers = @(
            @(1..$bottomColourLayers) +
            @(if ($topColourLayers -gt 0) { ($totalLayerCount - $topColourLayers + 1)..$totalLayerCount }) |
            Where-Object { $_ -ge 1 -and $_ -le $totalLayerCount } |
            Sort-Object -Unique
        )
        $slicePicker = [System.Windows.Forms.ComboBox]::new()
        $slicePicker.Location = [System.Drawing.Point]::new(558, 98)
        $slicePicker.Size = [System.Drawing.Size]::new(220, 27)
        $slicePicker.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
        foreach ($sliceLayer in $sliceLayers) { [void]$slicePicker.Items.Add("Layer $sliceLayer of $totalLayerCount") }
        $sliceInfo = [System.Windows.Forms.Label]::new()
        $sliceInfo.Location = [System.Drawing.Point]::new(790, 102)
        $sliceInfo.Size = [System.Drawing.Size]::new(298, 22)
        $sliceInfo.ForeColor = [System.Drawing.Color]::DarkSlateGray
        $sliceCanvas = [System.Windows.Forms.Panel]::new()
        $sliceCanvas.Location = [System.Drawing.Point]::new(558, 134)
        $sliceCanvas.Size = [System.Drawing.Size]::new(530, 410)
        $sliceCanvas.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
        if ($sliceLayers.Count -gt 0) { $sliceCanvas.Tag = [pscustomobject]@{ Layer = 1; Tool = $null }; $slicePicker.SelectedIndex = 0 }
        $sliceCanvas.Add_Paint({
            param($sender, $paint)
            $graphics = $paint.Graphics
            # Neutral grey makes both white and black filament visible.
            $graphics.Clear([System.Drawing.Color]::FromArgb(225, 225, 225))
            if ($null -eq $sender.Tag) {
                $graphics.DrawString('No printable layers were found.', $sender.Font, [System.Drawing.Brushes]::DimGray, 16, 16)
                return
            }
            $selection = $sender.Tag
            $selectedLayer = [int]$selection.Layer
            $selectedTool = $selection.Tool
            $layerPaths = @($colourLayerToolpaths | Where-Object { $_.Layer -eq $selectedLayer -and ($null -eq $selectedTool -or $_.Tool -eq [int]$selectedTool) })
            if ($layerPaths.Count -eq 0) {
                $middleMessage = if ($sliceLayers -notcontains $selectedLayer) { 'Middle single-colour layer intentionally ignored.' } else { "No extrusion paths found for layer $selectedLayer." }
                $graphics.DrawString($middleMessage, $sender.Font, [System.Drawing.Brushes]::DimGray, 16, 16)
                return
            }
            $allX = @($layerPaths | ForEach-Object { $_.X1; $_.X2 })
            $allY = @($layerPaths | ForEach-Object { $_.Y1; $_.Y2 })
            $minX = ($allX | Measure-Object -Minimum).Minimum; $maxX = ($allX | Measure-Object -Maximum).Maximum
            $minY = ($allY | Measure-Object -Minimum).Minimum; $maxY = ($allY | Measure-Object -Maximum).Maximum
            $rangeX = [Math]::Max(0.01, $maxX - $minX); $rangeY = [Math]::Max(0.01, $maxY - $minY)
            $scale = [Math]::Min(($sender.ClientSize.Width - 24) / $rangeX, ($sender.ClientSize.Height - 24) / $rangeY)
            # Draw extrusion at approximately a 0.45 mm bead width. This is
            # intentionally a material-coverage view, not a thin toolpath map.
            $beadWidth = [Math]::Max(2.0, 0.45 * $scale)
            $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
            foreach ($path in $layerPaths) {
                $pen = [System.Drawing.Pen]::new($previewToolColours[[int]$path.Tool], $beadWidth)
                $pen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
                $pen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
                $pen.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Round
                $x1 = 12 + (($path.X1 - $minX) * $scale); $y1 = $sender.ClientSize.Height - 12 - (($path.Y1 - $minY) * $scale)
                $x2 = 12 + (($path.X2 - $minX) * $scale); $y2 = $sender.ClientSize.Height - 12 - (($path.Y2 - $minY) * $scale)
                $graphics.DrawLine($pen, $x1, $y1, $x2, $y2)
                $pen.Dispose()
            }
        }.GetNewClosure())
        $updateSliceInfo = {
            $selection = $sliceCanvas.Tag
            if ($null -eq $selection) { $sliceInfo.Text = ''; return }
            $shownTool = if ($null -eq $selection.Tool) { 'All colours' } else { "$($previewToolLabels[[int]$selection.Tool]) only" }
            $zText = if ($layerHeights.ContainsKey([int]$selection.Layer)) { ('Z {0:N2} mm' -f $layerHeights[[int]$selection.Layer]) } else { 'Z unknown' }
            $sliceInfo.Text = "Layer $($selection.Layer)  |  $zText  |  $shownTool"
        }.GetNewClosure()
        $slicePicker.Add_SelectedIndexChanged({
            if ($slicePicker.SelectedIndex -ge 0) {
                $pickerLayer = [int]$sliceLayers[$slicePicker.SelectedIndex]
                $preservedTool = if ($null -ne $sliceCanvas.Tag -and [int]$sliceCanvas.Tag.Layer -eq $pickerLayer) { $sliceCanvas.Tag.Tool } else { $null }
                $sliceCanvas.Tag = [pscustomobject]@{ Layer = $pickerLayer; Tool = $preservedTool }
                $bar.Tag = $sliceCanvas.Tag
                $bar.Invalidate()
                & $updateSliceInfo
                $sliceCanvas.Invalidate()
            }
        }.GetNewClosure())
        $refreshGridButtons = $null
        $selectLayerFromBar = {
            param($sender, $mouse)
            $top = 24; $height = $sender.ClientSize.Height - 36
            if ($mouse.Y -lt $top -or $mouse.Y -ge ($top + $height)) { return }
            $ratio = [Math]::Max(0.0, [Math]::Min(0.9999, ($mouse.Y - $top) / [double]$height))
            $layer = [Math]::Max(1, [Math]::Min($totalLayerCount, $totalLayerCount - [int]($ratio * $totalLayerCount)))
            $left = 10; $width = $sender.ClientSize.Width - 20
            $labelWidth = 42; $cellsLeft = $left + $labelWidth; $cellsWidth = $width - $labelWidth
            $sequenceTools = @($layerSequenceTools[$layer])
            # Click the L# label to show all colours; click a colour cell to isolate it.
            $chosenTool = $null
            if ($mouse.X -ge $cellsLeft -and $mouse.X -lt ($cellsLeft + $cellsWidth) -and $sequenceTools.Count -gt 1) {
                $column = [Math]::Min($sequenceTools.Count - 1, [Math]::Max(0, [int](($mouse.X - $cellsLeft) * $sequenceTools.Count / $cellsWidth)))
                $chosenTool = [int]$sequenceTools[$column]
            }
            $selection = [pscustomobject]@{ Layer = $layer; Tool = $chosenTool }
            $bar.Tag = $selection
            $sliceCanvas.Tag = $selection
            $pickerIndex = [array]::IndexOf([int[]]$sliceLayers, [int]$layer)
            if ($pickerIndex -ge 0) { $slicePicker.SelectedIndex = $pickerIndex }
            else { $slicePicker.SelectedIndex = -1 }
            # SelectedIndexChanged does not fire when clicking another half of
            # the already selected layer, so always force a preview refresh.
            & $updateSliceInfo
            $bar.Invalidate()
            $sliceCanvas.Invalidate()
            # Do not rebuild controls from inside their own Click event. It
            # can leave a stale control under the pointer. Update their real
            # borders in place; controls are rebuilt only on a window resize.
            foreach ($cellControl in $bar.Controls) {
                if ($cellControl -is [System.Windows.Forms.Button] -and $null -ne $cellControl.Tag -and $null -ne $cellControl.Tag.PSObject.Properties['Tool']) {
                    $isActiveCell = [int]$cellControl.Tag.Layer -eq $layer -and $null -ne $chosenTool -and [int]$cellControl.Tag.Tool -eq [int]$chosenTool
                    $cellControl.FlatAppearance.BorderSize = if ($isActiveCell) { 3 } else { 1 }
                    $cellControl.FlatAppearance.BorderColor = if ($isActiveCell) { [System.Drawing.Color]::DarkOrange } else { [System.Drawing.Color]::DimGray }
                }
            }
        }.GetNewClosure()
        # The grid below owns all selection.  Keep the Panel itself inert so a
        # background click can never be interpreted as a neighbouring cell.

        $selectGridCell = {
            param([int]$gridLayer, $gridTool)
            $selection = [pscustomobject]@{ Layer = $gridLayer; Tool = $gridTool }
            $bar.Tag = $selection
            $sliceCanvas.Tag = $selection
            $pickerIndex = [array]::IndexOf([int[]]$sliceLayers, $gridLayer)
            if ($pickerIndex -ge 0) { $slicePicker.SelectedIndex = $pickerIndex } else { $slicePicker.SelectedIndex = -1 }
            & $updateSliceInfo
            $sliceCanvas.Invalidate()
            foreach ($cellControl in $bar.Controls) {
                if ($cellControl -is [System.Windows.Forms.Button] -and $null -ne $cellControl.Tag -and $null -ne $cellControl.Tag.PSObject.Properties['Tool']) {
                    $isActiveCell = $null -ne $gridTool -and [int]$cellControl.Tag.Layer -eq $gridLayer -and $null -ne $cellControl.Tag.Tool -and [int]$cellControl.Tag.Tool -eq [int]$gridTool
                    $cellControl.FlatAppearance.BorderSize = if ($isActiveCell) { 3 } else { 1 }
                    $cellControl.FlatAppearance.BorderColor = if ($isActiveCell) { [System.Drawing.Color]::DarkOrange } else { [System.Drawing.Color]::DimGray }
                }
            }
        }.GetNewClosure()

        $gridActions = [pscustomobject]@{ Refresh = $null; Summary = $null }
        $moveGridCell = {
            param($sourceTag, $targetTag)
            if ($null -eq $sourceTag -or $null -eq $targetTag) { return }
            if ([int]$sourceTag.Layer -ne [int]$targetTag.Layer) { return }
            $moveLayer = [int]$sourceTag.Layer
            $fromIndex = [int]$sourceTag.Index; $toIndex = [int]$targetTag.Index
            if ($moveLayer -gt $bottomColourLayers) { return }
            if ($fromIndex -lt 0 -or $toIndex -lt 0 -or $fromIndex -eq $toIndex) { return }
            if ($fromIndex -ge @($layerSequenceTools[$moveLayer]).Count -or $toIndex -ge @($layerSequenceTools[$moveLayer]).Count) { return }
            $working = [System.Collections.Generic.List[int]]::new()
            foreach ($workingTool in @($layerSequenceTools[$moveLayer])) { $working.Add([int]$workingTool) }
            $movedTool = $working[$fromIndex]
            # Dropping one colour directly on another swaps the two cells. It
            # is predictable in short 2- or 3-colour rows and works in either
            # drag direction.
            $working[$fromIndex] = $working[$toIndex]
            $working[$toIndex] = $movedTool
            $layerSequenceTools[$moveLayer] = $working.ToArray()
            if ($null -ne $gridActions.Refresh) { & $gridActions.Refresh }
            if ($null -ne $gridActions.Summary) { & $gridActions.Summary }
            & $selectGridCell $moveLayer ([int]$movedTool)
        }.GetNewClosure()
        # All button event closures share this mutable object. A plain variable
        # would be copied into each GetNewClosure() and dragging would never
        # progress from MouseDown to MouseMove.
        $dragState = [pscustomobject]@{ Source = $null; Start = [System.Drawing.Point]::Empty }

        # A true spreadsheet-style grid: every row label and every colour is a
        # native Button. No painted hit regions or coordinate reconstruction.
        $refreshGridButtons = {
            # Nested GetNewClosure only captures locals in this invocation.
            # Copy the outer callbacks/state locally before wiring cell events.
            $selectGridCell = $selectGridCell
            $moveGridCell = $moveGridCell
            $dragState = $dragState
            $bar.Controls.Clear()
            $left = 10; $top = 24; $width = $bar.ClientSize.Width - 20; $height = $bar.ClientSize.Height - 36
            $labelWidth = 42; $cellsLeft = $left + $labelWidth; $cellsWidth = $width - $labelWidth
            $rowHeight = $height / [double]$totalForBar
            $header = [System.Windows.Forms.Label]::new()
            $header.Text = "PRINTING ORDER  ->  (up to $maxPreviewColours colours)"
            $header.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
            $header.ForeColor = [System.Drawing.Color]::DimGray
            $header.SetBounds($cellsLeft, 1, $cellsWidth, 22)
            [void]$bar.Controls.Add($header)
            for ($gridLayer = 1; $gridLayer -le $totalForBar; $gridLayer++) {
                $sequenceTools = @($layerSequenceTools[$gridLayer])
                $rowY = $top + [int](($totalForBar - $gridLayer) * $rowHeight)
                $rowBottom = $top + [int](($totalForBar - $gridLayer + 1) * $rowHeight)
                $rowPixels = [Math]::Max(1, $rowBottom - $rowY)
                $layerButton = [System.Windows.Forms.Button]::new()
                $layerButton.Text = "L $gridLayer"
                $layerButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
                $layerButton.TabStop = $false
                $layerButton.UseVisualStyleBackColor = $false
                $layerButton.BackColor = [System.Drawing.Color]::Gainsboro
                $layerButton.FlatAppearance.BorderSize = 1
                $layerButton.FlatAppearance.BorderColor = [System.Drawing.Color]::DimGray
                $layerButton.Tag = [pscustomobject]@{ Layer = $gridLayer; Tool = $null }
                $layerButton.SetBounds($left, $rowY, $labelWidth, $rowPixels)
                $layerButton.Add_Click({ param($sender, $event) & $selectGridCell ([int]$sender.Tag.Layer) $null }.GetNewClosure())
                [void]$bar.Controls.Add($layerButton)
                for ($gridCell = 0; $gridCell -lt $sequenceTools.Count; $gridCell++) {
                    $cellLeft = $cellsLeft + [int]($cellsWidth * $gridCell / $sequenceTools.Count)
                    $cellRight = $cellsLeft + [int]($cellsWidth * ($gridCell + 1) / $sequenceTools.Count)
                    $tool = [int]$sequenceTools[$gridCell]
                    $button = [System.Windows.Forms.Button]::new()
                    $button.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
                    $button.TabStop = $false
                    $button.UseVisualStyleBackColor = $false
                    $button.BackColor = $previewToolColours[$tool]
                    $button.FlatAppearance.MouseOverBackColor = $button.BackColor
                    $button.FlatAppearance.MouseDownBackColor = $button.BackColor
                    $isSelected = [int]$bar.Tag.Layer -eq $gridLayer -and $null -ne $bar.Tag.Tool -and [int]$bar.Tag.Tool -eq $tool
                    $button.FlatAppearance.BorderSize = if ($isSelected) { 3 } else { 1 }
                    $button.FlatAppearance.BorderColor = if ($isSelected) { [System.Drawing.Color]::DarkOrange } else { [System.Drawing.Color]::DimGray }
                    $button.AccessibleName = "Layer ${gridLayer}: $($previewToolLabels[$tool])"
                    $button.Tag = [pscustomobject]@{ Layer = $gridLayer; Tool = $tool; Index = $gridCell }
                    $button.AllowDrop = $gridLayer -le $bottomColourLayers
                    $button.Cursor = if ($button.AllowDrop) { [System.Windows.Forms.Cursors]::SizeAll } else { [System.Windows.Forms.Cursors]::Arrow }
                    $button.SetBounds($cellLeft, $rowY, [Math]::Max(1, $cellRight - $cellLeft), $rowPixels)
                    $button.Add_Click({
                        param($sender, $event)
                        & $selectGridCell ([int]$sender.Tag.Layer) ([int]$sender.Tag.Tool)
                    }.GetNewClosure())
                    $button.Add_MouseDown({
                        param($sender, $event)
                        if ($event.Button -eq [System.Windows.Forms.MouseButtons]::Left -and $sender.AllowDrop) {
                            $dragState.Source = $sender
                            $dragState.Start = $event.Location
                        }
                    }.GetNewClosure())
                    $button.Add_MouseMove({
                        param($sender, $event)
                        if ($event.Button -eq [System.Windows.Forms.MouseButtons]::Left -and $dragState.Source -eq $sender -and ([Math]::Abs($event.X - $dragState.Start.X) -ge 3 -or [Math]::Abs($event.Y - $dragState.Start.Y) -ge 3)) {
                            $dragState.Source = $null
                            [void]$sender.DoDragDrop("$($sender.Tag.Layer)|$($sender.Tag.Index)", [System.Windows.Forms.DragDropEffects]::Move)
                        }
                    }.GetNewClosure())
                    $button.Add_MouseUp({
                        param($sender, $event)
                        $dragState.Source = $null
                    }.GetNewClosure())
                    $button.Add_DragEnter({
                        param($sender, $event)
                        $dragText = [string]$event.Data.GetData([System.Windows.Forms.DataFormats]::Text)
                        if ($dragText -match '^(\d+)\|(\d+)$' -and [int]$Matches[1] -eq [int]$sender.Tag.Layer -and $sender.AllowDrop) {
                            $event.Effect = [System.Windows.Forms.DragDropEffects]::Move
                        } else { $event.Effect = [System.Windows.Forms.DragDropEffects]::None }
                    }.GetNewClosure())
                    $button.Add_DragDrop({
                        param($sender, $event)
                        $dragText = [string]$event.Data.GetData([System.Windows.Forms.DataFormats]::Text)
                        if ($dragText -match '^(\d+)\|(\d+)$') {
                            $sourceTag = [pscustomobject]@{ Layer = [int]$Matches[1]; Index = [int]$Matches[2] }
                            & $moveGridCell $sourceTag $sender.Tag
                        }
                    }.GetNewClosure())
                    [void]$bar.Controls.Add($button)
                }
            }
        }.GetNewClosure()
        $gridActions.Refresh = $refreshGridButtons
        $gridActions.Summary = {
            $summaryLines = [System.Collections.Generic.List[string]]::new()
            $summaryTool = [int]$layerSequenceTools[1][0]; $summaryPauses = 0
            $initialColour = $previewToolLabels[$summaryTool]
            for ($summaryLayer = 1; $summaryLayer -le $totalLayerCount; $summaryLayer++) {
                $summaryTools = @($layerSequenceTools[$summaryLayer])
                foreach ($summaryNext in $summaryTools) {
                    if ([int]$summaryNext -ne $summaryTool) { $summaryPauses++; $summaryTool = [int]$summaryNext }
                }
                if ($summaryLayer -le $bottomColourLayers -or $summaryLayer -gt ($totalLayerCount - $topColourLayers)) {
                    $summaryNames = @($summaryTools | ForEach-Object { $previewToolLabels[[int]$_] })
                    $summaryLines.Add("Layer ${summaryLayer}: " + ($summaryNames -join ' -> '))
                }
            }
            $heading.Text = "Bottom: $bottomColourLayers layer(s)     Top: $topColourLayers layer(s)     Manual pauses: $summaryPauses"
            $scheduleBox.Text = "EXPORT SUMMARY`r`n`r`nBottom colour layers: $bottomColourLayers`r`nTop colour layers: $topColourLayers`r`nTotal sliced layers: $totalLayerCount`r`nManual pauses: $summaryPauses`r`nInitial filament: $initialColour`r`nBase: slot $($baseTool + 1) - $($previewToolLabels[$baseTool])`r`n`r`nCOLOUR ORDER`r`n" + ($summaryLines -join "`r`n`r`n") + "`r`n`r`nMiddle layers use the base colour.`r`n`r`nFILAMENT SLOTS`r`n" + ($colourSummary -replace ', ', "`r`n")
            $scheduleBox.SelectionStart = 0
            $scheduleBox.SelectionLength = 0
        }.GetNewClosure()

        $finishBase = [System.Windows.Forms.Button]::new()
        $finishBase.Text = 'Finish bottom layers with base'
        $finishBase.Enabled = $bottomColourLayers -gt 0 -and $bottomColourLayers -lt ($totalLayerCount - $topColourLayers) -and @($layerSequenceTools[$bottomColourLayers]).Count -gt 1 -and [array]::IndexOf([int[]]$layerSequenceTools[$bottomColourLayers], $baseTool) -ge 0
        $finishBase.Add_Click({
            $baseRow = @($layerSequenceTools[$bottomColourLayers])
            $baseIndex = [array]::IndexOf([int[]]$baseRow, $baseTool)
            if ($baseIndex -ge 0 -and $baseIndex -lt ($baseRow.Count - 1)) {
                & $moveGridCell ([pscustomobject]@{ Layer = $bottomColourLayers; Index = $baseIndex }) ([pscustomobject]@{ Layer = $bottomColourLayers; Index = $baseRow.Count - 1 })
            }
        }.GetNewClosure())

        $cancel = [System.Windows.Forms.Button]::new(); $cancel.Text = 'Cancel export'; $cancel.Location = [System.Drawing.Point]::new(874, 560); $cancel.Size = [System.Drawing.Size]::new(102, 32)
        $continue = [System.Windows.Forms.Button]::new(); $continue.Text = 'Write G-code'; $continue.Location = [System.Drawing.Point]::new(986, 560); $continue.Size = [System.Drawing.Size]::new(102, 32)
        $cancel.Add_Click({ $preview.DialogResult = [System.Windows.Forms.DialogResult]::Cancel; $preview.Close() })
        $continue.Add_Click({ $preview.DialogResult = [System.Windows.Forms.DialogResult]::Yes; $preview.Close() })

        # Preview-first responsive layout. The colour stack stays broad enough
        # for reliable cell selection, then all three panes scale with the form.
        $layoutPreview = {
            $margin = 18; $gap = 12; $contentTop = 74; $buttonArea = 58
            $clientWidth = $preview.ClientSize.Width; $clientHeight = $preview.ClientSize.Height
            $availableWidth = $clientWidth - (2 * $margin) - (2 * $gap)
            $barWidth = [Math]::Max(280, [int]($availableWidth * 0.31))
            $scheduleWidth = [Math]::Max(270, [int]($availableWidth * 0.27))
            $sliceWidth = [Math]::Max(300, $availableWidth - $barWidth - $scheduleWidth)
            $contentHeight = [Math]::Max(360, $clientHeight - $contentTop - $buttonArea)
            $scheduleX = $margin + $barWidth + $gap
            $sliceX = $scheduleX + $scheduleWidth + $gap

            $heading.SetBounds($margin, 16, $clientWidth - (2 * $margin), 24)
            $hint.SetBounds($margin, 44, $clientWidth - (2 * $margin), 22)
            $bar.SetBounds($margin, $contentTop, $barWidth, $contentHeight)
            $scheduleBox.SetBounds($scheduleX, $contentTop, $scheduleWidth, $contentHeight)
            $sliceLabel.SetBounds($sliceX, $contentTop, $sliceWidth, 20)
            $slicePicker.SetBounds($sliceX, $contentTop + 24, 230, 27)
            $sliceInfo.SetBounds($sliceX + 242, $contentTop + 28, [Math]::Max(80, $sliceWidth - 242), 22)
            $sliceCanvas.SetBounds($sliceX, $contentTop + 60, $sliceWidth, $contentHeight - 60)
            $continue.SetBounds($clientWidth - $margin - 102, $clientHeight - 42, 102, 32)
            $cancel.SetBounds($clientWidth - $margin - 214, $clientHeight - 42, 102, 32)
            $finishBase.SetBounds($margin, $clientHeight - 42, 245, 32)
            $bar.Invalidate(); $sliceCanvas.Invalidate(); if ($null -ne $refreshGridButtons) { & $refreshGridButtons }
        }.GetNewClosure()
        $preview.Add_Resize({ & $layoutPreview }.GetNewClosure())
        [IO.File]::AppendAllText($previewTracePath, "PID=$PID Controls built; laying out`r`n")
        & $updateSliceInfo
        $preview.Controls.AddRange(@($heading, $hint, $bar, $scheduleBox, $sliceLabel, $slicePicker, $sliceInfo, $sliceCanvas, $cancel, $continue, $finishBase))
        & $layoutPreview
        [IO.File]::AppendAllText($previewTracePath, "PID=$PID Layout complete`r`n")
        # Windows may refuse focus stealing from a background watcher. Request
        # activation once, then flash the taskbar if it remains in the background.
        # Keep only the confirmation window topmost until it closes.
        if (-not ('ManualMulticolor.PreviewAttention' -as [type])) {
            Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace ManualMulticolor {
    public static class PreviewAttention {
        [StructLayout(LayoutKind.Sequential)]
        private struct FLASHWINFO {
            public uint cbSize;
            public IntPtr hwnd;
            public uint dwFlags;
            public uint uCount;
            public uint dwTimeout;
        }
        [DllImport("user32.dll")]
        public static extern bool SetForegroundWindow(IntPtr hwnd);
        [DllImport("user32.dll")]
        public static extern IntPtr GetForegroundWindow();
        [DllImport("user32.dll")]
        private static extern bool FlashWindowEx(ref FLASHWINFO info);
        public static void Flash(IntPtr hwnd) {
            var info = new FLASHWINFO();
            info.cbSize = (uint)Marshal.SizeOf(typeof(FLASHWINFO));
            info.hwnd = hwnd;
            info.dwFlags = 3; // Caption and taskbar; finite attention request.
            info.uCount = 5;
            FlashWindowEx(ref info);
        }
    }
}
'@
        }
        $preview.ShowInTaskbar = $true
        $preview.TopMost = $true
        $preview.Add_Shown({
            param($sender, $eventArgs)
            [IO.File]::AppendAllText($previewTracePath, "PID=$PID Shown event`r`n")
            $sender.TopMost = $true
            $sender.BringToFront()
            $sender.Activate()
            [void][ManualMulticolor.PreviewAttention]::SetForegroundWindow($sender.Handle)
            if ([ManualMulticolor.PreviewAttention]::GetForegroundWindow() -ne $sender.Handle) {
                [ManualMulticolor.PreviewAttention]::Flash($sender.Handle)
            }
        })
        $choice = $preview.ShowDialog()
        [IO.File]::AppendAllText($previewTracePath, "PID=$PID Dialog result: $choice`r`n")
        if ($choice -ne [System.Windows.Forms.DialogResult]::Yes) {
            throw 'Manual-colour export cancelled by user.'
        }
    } catch {
        if ($_.Exception.Message -eq 'Manual-colour export cancelled by user.') { throw }
        throw "Manual-colour preview failed; export was not written: $($_.Exception.Message)"
    }
}

# Apply any drag-and-drop choices made in the export preview.  This happens
# before manual M600 conversion, while the virtual-tool blocks still exist.
$bottomOrderChanged = $false
for ($compareLayer=1; $compareLayer -le $bottomColourLayers; $compareLayer++) {
    if (($originalBottomOrders[$compareLayer] -join ',') -ne ($layerSequenceTools[$compareLayer] -join ',')) { $bottomOrderChanged = $true }
}
$initialTool = [int]$layerSequenceTools[1][0]
if ($bottomOrderChanged) {
    . (Join-Path $PSScriptRoot 'ReorderColourBlocks.ps1')
    $lines = Reorder-FreeBottomLayers $lines $layerSequenceTools $bottomColourLayers
} else {
    $lines = Reorder-ManualColourLayerBlocks $lines $layerSequenceTools
}

# A reordered final bottom colour can already be the base filament.  In that
# case no extra pause is needed before the middle single-colour section.
if ($bottomColourLayers -gt 0 -and $layerSequenceTools.ContainsKey($bottomColourLayers)) {
    $lastBottomTool = [int](@($layerSequenceTools[$bottomColourLayers])[-1])
    $baseReturnIsNeeded = $lastBottomTool -ne $baseTool -and $baseReturnLayer -le $totalLayerCount -and -not ($topColourLayers -gt 0 -and $baseReturnLayer -gt ($totalLayerCount - $topColourLayers))
}

# Plan first-layer purge lanes beside the model. East/X+ is preferred because
# it is normally the shortest clear trip from these centered sign/keychain
# layouts. Fall back to west, then the front edge if bed clearance is tight.
$bedMaxX = 250.0; $bedMaxY = 210.0
foreach ($bedLine in $lines) {
    if ($bedLine -match '^; bed_shape = (.+)$') {
        $bedPoints = [regex]::Matches($Matches[1], '(-?[0-9.]+)x(-?[0-9.]+)')
        if ($bedPoints.Count -gt 0) {
            $bedMaxX = [double](($bedPoints | ForEach-Object { [double]$_.Groups[1].Value } | Measure-Object -Maximum).Maximum)
            $bedMaxY = [double](($bedPoints | ForEach-Object { [double]$_.Groups[2].Value } | Measure-Object -Maximum).Maximum)
        }
        break
    }
}
$purgeLayout = [pscustomobject]@{ Mode = 'Front'; BaseX = 55.0; BaseY = -2.5; YStart = 5.0; YEnd = 40.0 }
$firstLayerPathsForPurge = @(Get-ColourLayerToolpaths $lines 1 0 $totalLayerCount | Where-Object { $_.Layer -eq 1 })
if ($firstLayerPathsForPurge.Count -gt 0) {
    $modelMinX = [double](($firstLayerPathsForPurge | ForEach-Object { [Math]::Min($_.X1, $_.X2) } | Measure-Object -Minimum).Minimum)
    $modelMaxX = [double](($firstLayerPathsForPurge | ForEach-Object { [Math]::Max($_.X1, $_.X2) } | Measure-Object -Maximum).Maximum)
    $modelMinY = [double](($firstLayerPathsForPurge | ForEach-Object { [Math]::Min($_.Y1, $_.Y2) } | Measure-Object -Minimum).Minimum)
    $modelMaxY = [double](($firstLayerPathsForPurge | ForEach-Object { [Math]::Max($_.Y1, $_.Y2) } | Measure-Object -Maximum).Maximum)
    $firstLayerChangeCount = @($plannedEvents | Where-Object { $_.Layer -eq 1 }).Count
    $laneWidthNeeded = 5.0 + [Math]::Max(1, $firstLayerChangeCount) * 1.4
    $purgeLength = [Math]::Min(35.0, [Math]::Max(18.0, $modelMaxY - $modelMinY))
    $purgeCenterY = ($modelMinY + $modelMaxY) / 2.0
    $purgeStartY = [Math]::Max(3.0, [Math]::Min($bedMaxY - $purgeLength - 3.0, $purgeCenterY - $purgeLength / 2.0))
    if (($modelMaxX + $laneWidthNeeded) -le ($bedMaxX - 2.0)) {
        $purgeLayout = [pscustomobject]@{ Mode = 'East'; BaseX = $modelMaxX + 3.0; BaseY = 0.0; YStart = $purgeStartY; YEnd = $purgeStartY + $purgeLength }
    } elseif (($modelMinX - $laneWidthNeeded) -ge 2.0) {
        $purgeLayout = [pscustomobject]@{ Mode = 'West'; BaseX = $modelMinX - 3.0; BaseY = 0.0; YStart = $purgeStartY; YEnd = $purgeStartY + $purgeLength }
    }
}
$skipManualLines = 0
$removedChanges = 0
$pendingM600Colour = $null
$pendingM600Label = $null
$pendingFirstLayerPurge = $false
$pendingResumeX = $null
$pendingResumeY = $null
$pendingResumeZ = $null
$skipReplacedPressurePrime = $false
$firstLayerPurgeIndex = 0
$currentSegmentNumber = 0
$filenameTools = [System.Collections.Generic.HashSet[int]]::new()
[void]$filenameTools.Add($initialTool)
[void]$filenameTools.Add($baseTool)
# Track the last deposited line so a colour change can wipe backward within
# the outgoing colour immediately before the M600 parking move.
$trackX = $null; $trackY = $null; $trackE = 0.0; $trackRelativeE = $true
$lastExtrusion = $null

$lineIndex = -1
foreach ($line in $lines) {
    $lineIndex++
    if ($skipManualLines -gt 0) {
        $skipManualLines--
        continue
    }
    if ($skipReplacedPressurePrime) {
        $skipReplacedPressurePrime = $false
        if ($line -match '^G1\s+E0\.8\s+F300\s*;\s*rebuild nozzle pressure') { continue }
    }

    if ($line -match '^M82(?:\s|$)') { $trackRelativeE = $false }
    elseif ($line -match '^M83(?:\s|$)') { $trackRelativeE = $true }
    elseif ($line -match '^G92\s+.*\bE(-?[0-9.]+)') { $trackE = [double]$Matches[1] }
    elseif ($line -match '^G[123](?:\s|$)') {
        $xMatch = [regex]::Match($line, '(?:^|\s)X(-?[0-9.]+)')
        $yMatch = [regex]::Match($line, '(?:^|\s)Y(-?[0-9.]+)')
        $eMatch = [regex]::Match($line, '(?:^|\s)E(-?[0-9.]+)')
        $nextX = if ($xMatch.Success) { [double]$xMatch.Groups[1].Value } else { $trackX }
        $nextY = if ($yMatch.Success) { [double]$yMatch.Groups[1].Value } else { $trackY }
        if ($eMatch.Success) {
            $e = [double]$eMatch.Groups[1].Value
            $isExtruding = if ($trackRelativeE) { $e -gt 0 } else { $e -gt ($trackE + 0.00001) }
            if ($isExtruding -and $null -ne $trackX -and $null -ne $trackY -and $null -ne $nextX -and $null -ne $nextY) {
                $lastExtrusion = [pscustomobject]@{ X1 = [double]$trackX; Y1 = [double]$trackY; X2 = [double]$nextX; Y2 = [double]$nextY }
            }
            if (-not $trackRelativeE) { $trackE = $e }
        }
        $trackX = $nextX; $trackY = $nextY
    }

    if ($line -match '^;LAYER_CHANGE\s*$') {
        $layerCount++
        $currentSegmentNumber = 1
        $output.Add($line)
        if ($layerCount -eq 1) { $output.Add("; MANUAL_COLOUR_INITIAL=$(Get-ToolLabel $initialTool)") }
        $firstLayerTool = 0
        if ($layerSequenceTools.ContainsKey($layerCount) -and @($layerSequenceTools[$layerCount]).Count -gt 0) {
            $firstLayerTool = [int]@($layerSequenceTools[$layerCount])[0]
        }
        $output.Add("M118 MCP_SEGMENT L=$layerCount S=1 C=`"$(Get-ToolLabel $firstLayerTool)`"")
        $isTopColourLayer = $topColourLayers -gt 0 -and $layerCount -gt ($totalLayerCount - $topColourLayers)
        if ($baseReturnIsNeeded -and $layerCount -eq $baseReturnLayer -and -not $isTopColourLayer) {
            $baseLabel = Get-ToolLabel $baseTool
            $output.Add("; MANUAL_COLOUR_LIMIT: load base colour after layer $bottomColourLayers")
            $output.Add('M400 ; finish queued moves')
            $output.Add("M117 Load $baseLabel")
            $output.Add(";COLOR_CHANGE,T0,$(Get-ToolHexColour $baseTool)")
            $baseResumeX = $null; $baseResumeY = $null
            for ($baseResumeIndex = $lineIndex + 1; $baseResumeIndex -lt $lines.Count; $baseResumeIndex++) {
                $baseResumeLine = $lines[$baseResumeIndex]
                if ($baseResumeLine -eq ';LAYER_CHANGE' -or $baseResumeLine -eq '; MANUAL_COLOUR_TOOLCHANGE') { break }
                if ($baseResumeLine -match '^G[01](?:\s|$)') {
                    $baseXMatch = [regex]::Match($baseResumeLine, '(?:^|\s)X(-?[0-9.]+)')
                    $baseYMatch = [regex]::Match($baseResumeLine, '(?:^|\s)Y(-?[0-9.]+)')
                    if ($baseXMatch.Success -and $baseYMatch.Success) {
                        $baseResumeX = [double]$baseXMatch.Groups[1].Value
                        $baseResumeY = [double]$baseYMatch.Groups[1].Value
                        break
                    }
                }
            }
            if ($null -ne $baseResumeX -and $null -ne $baseResumeY) {
                $baseResumeZ = if ($layerHeights.ContainsKey($layerCount)) { [double]$layerHeights[$layerCount] + 0.4 } else { $null }
                if ($null -ne $baseResumeZ) { $output.Add("G1 Z$(Format-GcodeNumber $baseResumeZ) F720 ; lift before moving to base colour start") }
                $output.Add("G1 X$(Format-GcodeNumber $baseResumeX) Y$(Format-GcodeNumber $baseResumeY) F18000 ; fast travel to base colour start and set M600 resume point")
                $output.Add('; MANUAL_COLOUR_RESUME_AT_NEXT_START')
            }
            $output.Add("M600 E0.8 C`"$(Get-ToolHexColour $baseTool)`" ; retract before parking; load base colour: $baseLabel")
            $output.Add("M118 MCP_SEGMENT L=$layerCount S=1 C=`"$baseLabel`"")
            $output.Add('G1 E0.8 F300 ; rebuild nozzle pressure after manual colour change')
        }
        continue
    }

    $isBottomColourLayer = $layerCount -ge 1 -and $layerCount -le $bottomColourLayers
    $isTopColourLayer = $topColourLayers -gt 0 -and $layerCount -gt ($totalLayerCount - $topColourLayers)
    $isColourLayer = $isBottomColourLayer -or $isTopColourLayer
    if ($line -eq '; MANUAL_COLOUR_LAYER_ENTRY') { $currentSegmentNumber = 0; continue }

    if (($layerCount -eq 0 -or -not $isColourLayer) -and $line -eq '; MANUAL_COLOUR_TOOLCHANGE') {
        # The profile emits this marker followed by M600, its prime, and a
        # virtual Tn command. None of those should run above the first layer.
        $skipManualLines = 3
        if ($layerCount -gt 0) { $removedChanges++ }
        continue
    }

    if ($isColourLayer -and $line -eq '; MANUAL_COLOUR_TOOLCHANGE') {
        $tool = 0
        if ($lineIndex + 3 -lt $lines.Count -and $lines[$lineIndex + 3] -match '^\s*T(\d+)(?:\s*;.*)?$') {
            $tool = [int] $Matches[1]
        }
        $label = Get-ToolLabel $tool
        [void]$filenameTools.Add($tool)
        $output.Add($line)
        if ($null -ne $lastExtrusion) {
            $dx = $lastExtrusion.X1 - $lastExtrusion.X2
            $dy = $lastExtrusion.Y1 - $lastExtrusion.Y2
            $length = [Math]::Sqrt($dx * $dx + $dy * $dy)
            if ($length -gt 0.001) {
                # Backtrack over the outgoing extrusion before leaving it. A
                # 2.5 mm wipe anchors the tail without travelling outside the
                # path that was just printed.
                $wipeLength = [Math]::Min(2.5, $length)
                $wipeX = $lastExtrusion.X2 + ($dx / $length * $wipeLength)
                $wipeY = $lastExtrusion.Y2 + ($dy / $length * $wipeLength)
                $output.Add("G1 X$(Format-GcodeNumber $wipeX) Y$(Format-GcodeNumber $wipeY) F6000 ; reverse wipe 2.5 mm within outgoing colour")
            }
        }
        $output.Add("M117 Load $label")
        $output.Add(";COLOR_CHANGE,T0,$(Get-ToolHexColour $tool)")
        $pendingM600Colour = Get-ToolHexColour $tool
        $pendingM600Label = $label
        $pendingFirstLayerPurge = $layerCount -eq 1
        # M600 returns to the position at which it was invoked. Find the first
        # XY travel belonging to the incoming colour and make that the saved
        # resume position, rather than the outgoing colour's final endpoint.
        $pendingResumeX = $null
        $pendingResumeY = $null
        $pendingResumeZ = if ($layerHeights.ContainsKey($layerCount)) { [double]$layerHeights[$layerCount] + 0.4 } else { $null }
        $seenResumeM600 = $false
        $insideExistingPurge = $false
        for ($resumeIndex = $lineIndex + 1; $resumeIndex -lt $lines.Count; $resumeIndex++) {
            $resumeLine = $lines[$resumeIndex]
            if ($resumeIndex -gt ($lineIndex + 3) -and ($resumeLine -eq '; MANUAL_COLOUR_TOOLCHANGE' -or $resumeLine -eq ';LAYER_CHANGE')) { break }
            if ($resumeLine -match '^\s*M600(?:\s|$)') { $seenResumeM600 = $true; continue }
            if ($resumeLine -match '^; MANUAL_COLOUR_PURGE_STRIP=') { $insideExistingPurge = $true; continue }
            if ($insideExistingPurge -and $resumeLine -match '^M400\s*;\s*complete purge strip') { $insideExistingPurge = $false; continue }
            if ($seenResumeM600 -and -not $insideExistingPurge -and $resumeLine -match '^G[01](?:\s|$)') {
                $resumeXMatch = [regex]::Match($resumeLine, '(?:^|\s)X(-?[0-9.]+)')
                $resumeYMatch = [regex]::Match($resumeLine, '(?:^|\s)Y(-?[0-9.]+)')
                if ($resumeXMatch.Success -and $resumeYMatch.Success) {
                    $pendingResumeX = [double]$resumeXMatch.Groups[1].Value
                    $pendingResumeY = [double]$resumeYMatch.Groups[1].Value
                    break
                }
            }
        }
        continue
    }

    if ($null -ne $pendingM600Colour -and $line -match '^\s*M600(?:\s|$)') {
        if ($null -ne $pendingResumeX -and $null -ne $pendingResumeY) {
            if ($null -ne $pendingResumeZ) {
                $output.Add("G1 Z$(Format-GcodeNumber $pendingResumeZ) F720 ; lift before moving to incoming colour start")
            }
            $output.Add("G1 X$(Format-GcodeNumber $pendingResumeX) Y$(Format-GcodeNumber $pendingResumeY) F18000 ; fast travel to incoming colour start and set M600 resume point")
            $output.Add('; MANUAL_COLOUR_RESUME_AT_NEXT_START')
        }
        $output.Add("M600 E0.8 C`"$pendingM600Colour`"")
        if ($pendingFirstLayerPurge) {
            # Use a fresh two-line lane beside Prusa's startup purge. The Z
            # lift keeps the travel string above the first-layer surface; the
            # following slicer-generated retract handles travel back to the
            # next model toolpath.
            $purgeZ = if ($layerHeights.ContainsKey(1)) { [double]$layerHeights[1] } else { 0.2 }
            $travelZ = $purgeZ + 0.4
            $output.Add("; MANUAL_COLOUR_PURGE_STRIP=$(Get-M600ColourText $pendingM600Label)")
            $output.Add("; MANUAL_COLOUR_PURGE_POSITION=$($purgeLayout.Mode)")
            $output.Add("M117 Purging $pendingM600Label")
            $output.Add("G1 Z$(Format-GcodeNumber $travelZ) F720 ; lift above first layer for purge travel")
            if ($purgeLayout.Mode -eq 'Front') {
                $purgeY1 = $purgeLayout.BaseY + (1.4 * $firstLayerPurgeIndex)
                $purgeY2 = $purgeY1 + 0.6
                $output.Add("G1 X55 Y$(Format-GcodeNumber $purgeY1) F9000 ; move to front purge fallback")
                $output.Add("G1 Z$(Format-GcodeNumber $purgeZ) F720")
                $output.Add("G1 X90 E1.5 F600 ; purge and establish nozzle pressure")
                $output.Add("G1 Y$(Format-GcodeNumber $purgeY2) F1200")
                $output.Add("G1 X55 E1.5 F600 ; second purge pass")
            } else {
                $laneDirection = if ($purgeLayout.Mode -eq 'East') { 1.0 } else { -1.0 }
                $purgeX1 = $purgeLayout.BaseX + ($laneDirection * 1.4 * $firstLayerPurgeIndex)
                $purgeX2 = $purgeX1 + ($laneDirection * 0.6)
                $output.Add("G1 X$(Format-GcodeNumber $purgeX1) Y$(Format-GcodeNumber $purgeLayout.YStart) F9000 ; move beside model on $($purgeLayout.Mode.ToLowerInvariant()) side")
                $output.Add("G1 Z$(Format-GcodeNumber $purgeZ) F720")
                $output.Add("G1 Y$(Format-GcodeNumber $purgeLayout.YEnd) E1.5 F600 ; purge and establish nozzle pressure")
                $output.Add("G1 X$(Format-GcodeNumber $purgeX2) F1200")
                $output.Add("G1 Y$(Format-GcodeNumber $purgeLayout.YStart) E1.5 F600 ; second purge pass")
            }
            $output.Add("M400 ; complete purge strip")
            $firstLayerPurgeIndex++
            $skipReplacedPressurePrime = $true
        }
        $currentSegmentNumber++
        $output.Add("M118 MCP_SEGMENT L=$layerCount S=$currentSegmentNumber C=`"$pendingM600Label`"")
        $pendingM600Colour = $null
        $pendingM600Label = $null
        $pendingFirstLayerPurge = $false
        $pendingResumeX = $null
        $pendingResumeY = $null
        $pendingResumeZ = $null
        continue
    }

    # Virtual tool IDs are slicer labels only; a single-nozzle MK4S must never
    # receive them. M600 is the actual manual change command.
    if ($line -match '^\s*T\d+(?:\s*;.*)?$') {
        continue
    }

    $output.Add($line)
}

if ($layerCount -lt 1) {
    throw 'No changes written: no PrusaSlicer layer markers were found.'
}

for ($metadataIndex = 0; $metadataIndex -lt $output.Count; $metadataIndex++) {
    if ($output[$metadataIndex] -match '^; MANUAL_COLOUR_TOP_LAYERS=') { $output[$metadataIndex] = "; MANUAL_COLOUR_TOP_LAYERS=$topColourLayers" }
}
$output.Insert(0, '; MANUAL_COLOUR_BASE_SLOT=' + ($baseTool + 1))
$output.Insert(0, '; MANUAL_COLOUR_USED_SLOTS=' + ((@($filenameTools | Sort-Object) | ForEach-Object { $_ + 1 }) -join ','))
[System.IO.File]::WriteAllLines($GcodePath, $output, [System.Text.UTF8Encoding]::new($false))
Write-Host "Preserved colour changes for the first $bottomColourLayers and last $topColourLayers layer(s); removed $removedChanges middle change(s)."
