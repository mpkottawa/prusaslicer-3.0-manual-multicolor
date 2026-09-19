[CmdletBinding()]
param(
    [string] $Folder = (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'PrusaManualMulticolor\exports'),
    [switch] $LibraryOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Test-ManualExport([string] $Name, [string] $Text) {
    if ($Name -match '(?i)-manual(?:-\d+)?\.gcode$') { return $false }
    if ($Text -match '(?m)^; MANUAL_COLOUR_(RESUME_AT_NEXT_START|LIMIT|PURGE_STRIP)' -or
        $Text -match '(?m)^M118 MCP_SEGMENT') { return $false }
    return (
        $Text -match '(?m)^; MANUAL_COLOUR_BOTTOM_LAYERS=[012]\s*$' -and
        $Text -match '(?m)^; MANUAL_COLOUR_TOP_LAYERS=[012]\s*$' -and
        $Text -match '(?m)^; MANUAL_COLOUR_TOOLCHANGE\s*$' -and
        $Text -match '(?m)^;LAYER_CHANGE\s*$' -and
        $Text -match '; prusaslicer_config = end\s*\z'
    )
}

function Read-CompletedExport([string] $Path) {
    # Exclusive access prevents reading while the exporter still holds the file.
    $stream = [IO.File]::Open($Path, 'Open', 'Read', 'None')
    try {
        $reader = [IO.StreamReader]::new($stream)
        try { return $reader.ReadToEnd() } finally { $reader.Dispose() }
    } finally { $stream.Dispose() }
}

function Get-FilenameColour([string] $Hex) {
    if ($Hex -notmatch '^#[0-9A-Fa-f]{6}$') { return 'Unknown' }
    # Broad color families for custom picker shades; explicit labels override these.
    Add-Type -AssemblyName System.Drawing
    $color = [Drawing.ColorTranslator]::FromHtml($Hex)
    $max = [Math]::Max($color.R, [Math]::Max($color.G, $color.B))
    $min = [Math]::Min($color.R, [Math]::Min($color.G, $color.B))
    if ($max -lt 45) { return 'Black' }
    if ($min -gt 225) { return 'White' }
    if (($max - $min) -lt 25) { return 'Grey' }
    $hue = $color.GetHue()
    if ($hue -lt 15 -or $hue -ge 345) { return 'Red' }
    if ($hue -lt 45) {
        if ($color.GetBrightness() -lt 0.45) { return 'Brown' }
        return 'Orange'
    }
    if ($hue -lt 70) { return 'Yellow' }
    if ($hue -lt 165) { return 'Green' }
    if ($hue -lt 195) { return 'Cyan' }
    if ($hue -lt 265) { return 'Blue' }
    if ($hue -lt 295) { return 'Purple' }
    return 'Pink'
}

function Get-UsedColourSuffix([string] $Text) {
    $slotsMatch = [regex]::Match($Text, '(?m)^; MANUAL_COLOUR_USED_SLOTS=([0-9,]+)\s*$')
    if (-not $slotsMatch.Success) { throw 'Processed file has no used-slot metadata; update the postprocessor.' }
    $colorsMatch = [regex]::Match($Text, '(?m)^; extruder_colour = ([^\r\n]+)')
    $colors = @(if ($colorsMatch.Success) { $colorsMatch.Groups[1].Value.Trim().Split(';') })
    $labelsMatch = [regex]::Match($Text, '(?m)^; MANUAL_COLOUR_LABELS=([^\r\n]+)')
    $labels = @(if ($labelsMatch.Success) { $labelsMatch.Groups[1].Value.Trim().Split(',') })
    $names = foreach ($slot in @($slotsMatch.Groups[1].Value.Split(',') | ForEach-Object { [int]$_ } | Sort-Object -Unique)) {
        $index = $slot - 1
        $name = if ($index -ge 0 -and $index -lt $labels.Count -and $labels[$index].Trim()) {
            $labels[$index].Trim()
        } elseif ($index -ge 0 -and $index -lt $colors.Count) {
            Get-FilenameColour $colors[$index].Trim()
        } else { "Slot$slot" }
        $name = [regex]::Replace($name, '[^\p{L}\p{N}-]+', '-')
        $name = $name.Trim('-')
        if (-not $name) { $name = "Slot$slot" }
        if ($name.Length -gt 24) { $name = $name.Substring(0, 24) }
        $name
    }
    return ($names -join '_')
}

function Convert-ExportCopy([string] $Path, [string] $Text, [string] $Processor) {
    $directory = [IO.Path]::GetDirectoryName($Path)
    $stem = [IO.Path]::GetFileNameWithoutExtension($Path)
    $pending = Join-Path $directory ('.manual-pending-' + [guid]::NewGuid().ToString('N') + '.tmp')
    try {
        # Automatic processing always asks for confirmation, regardless of export defaults.
        $Text = [regex]::Replace($Text, '(?m)^; MANUAL_COLOUR_EXPORT_CONFIRM=[01]\s*$', '')
        $Text = "; MANUAL_COLOUR_EXPORT_CONFIRM=1`n" + $Text
        [IO.File]::WriteAllText($pending, $Text, [Text.UTF8Encoding]::new($false))
        # The inherited processor warns if the UI fails. Treat that as a failure,
        # so an unconfirmed file is never published by the automatic workflow.
        $oldWarning = $WarningPreference
        $WarningPreference = 'Stop'
        try { & $Processor $pending | Out-Host } finally { $WarningPreference = $oldWarning }
        $suffix = Get-UsedColourSuffix ([IO.File]::ReadAllText($pending))
        $output = Join-Path $directory ($stem + '_' + $suffix + '-manual.gcode')
        $counter = 1
        while (Test-Path -LiteralPath $output) {
            $output = Join-Path $directory ($stem + '_' + $suffix + '-manual-' + $counter + '.gcode')
            $counter++
        }
        # File.Move fails rather than overwriting if another process creates this name.
        [IO.File]::Move($pending, $output)
        return $output
    } finally {
        if ([IO.File]::Exists($pending)) { [IO.File]::Delete($pending) }
    }
}

if ($LibraryOnly) { return }

$Folder = [IO.Path]::GetFullPath($Folder)
if (-not (Test-Path -LiteralPath $Folder -PathType Container)) { throw "Export folder not found: $Folder" }
$processor = Join-Path $PSScriptRoot 'FlattenManualColoursAboveFirstLayer.ps1'
if (-not (Test-Path -LiteralPath $processor)) { throw "Processor not found: $processor" }
$hash = [Security.Cryptography.SHA256]::Create()
try { $key = [BitConverter]::ToString($hash.ComputeHash([Text.Encoding]::UTF8.GetBytes($Folder.ToLowerInvariant()))).Replace('-', '') }
finally { $hash.Dispose() }
$created = $false
$mutex = [Threading.Mutex]::new($true, ('Local\PrusaManualMulticolor-' + $key), [ref] $created)
if (-not $created) { $mutex.Dispose(); Write-Host 'A watcher already owns this export folder; no duplicate started.'; return }

$logDir = Join-Path $env:LOCALAPPDATA 'PrusaManualMulticolor'
[IO.Directory]::CreateDirectory($logDir) | Out-Null
$log = Join-Path $logDir 'watcher.log'
function Write-WatcherLog([string] $Message) {
    Write-Host ('{0:HH:mm:ss} {1}' -f [DateTime]::Now, $Message)
    [IO.File]::AppendAllText($log, ('{0:s} {1}{2}' -f [DateTime]::Now, $Message, [Environment]::NewLine))
}

Write-WatcherLog 'Startup: loading tray interface'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()
$context = [Windows.Forms.ApplicationContext]::new()
$tray = [Windows.Forms.NotifyIcon]::new()
$tray.Icon = [Drawing.SystemIcons]::Application
$tray.Text = 'Manual Multicolor: watching exports'
$tray.Visible = $true
Write-WatcherLog 'Startup: tray created'
$menu = [Windows.Forms.ContextMenuStrip]::new()
$stop = $menu.Items.Add('Stop manual multicolor watcher')
$stop.Add_Click({ $context.ExitThread() })
$tray.ContextMenuStrip = $menu
$seen = @{}
$waiting = @{}
function Get-ExportSignature($File) { return "$($File.Length):$($File.LastWriteTimeUtc.Ticks)" }
# Ignore all pre-existing files. Re-exporting an existing filename will trigger it.
foreach ($file in Get-ChildItem -LiteralPath $Folder -Filter '*.gcode' -File) {
    $seen[$file.FullName] = Get-ExportSignature $file
}
Write-WatcherLog 'Startup: existing files indexed'
# Never inherit the regression hook into an interactive watcher.
Remove-Item Env:MANUAL_COLOUR_TEST_ORDER -ErrorAction SilentlyContinue
$timer = [Windows.Forms.Timer]::new()
$timer.Interval = 2000
$timer.Add_Tick({
    $timer.Stop()
    try {
        foreach ($file in Get-ChildItem -LiteralPath $Folder -Filter '*.gcode' -File) {
            $path = $file.FullName
            if ($file.Name -match '(?i)-manual(?:-\d+)?\.gcode$') { continue }
            $signature = Get-ExportSignature $file
            if ($seen.ContainsKey($path) -and $seen[$path] -eq $signature) { continue }
            if (-not $waiting.ContainsKey($path) -or $waiting[$path].Signature -ne $signature) {
                Write-WatcherLog "Detected export; waiting for writing to finish: $path"
                $waiting[$path] = @{Signature = $signature; Since = [DateTime]::UtcNow}
                continue
            }
            if (([DateTime]::UtcNow - $waiting[$path].Since).TotalSeconds -lt 4) { continue }
            try { $text = Read-CompletedExport $path } catch { continue }
            # A file without the completion footer may still be arriving in chunks.
            if ($text -notmatch '; prusaslicer_config = end\s*\z') { continue }
            $seen[$path] = $signature
            $waiting.Remove($path)
            if (-not (Test-ManualExport $file.Name $text)) {
                Write-WatcherLog "Skipped: already processed or missing manual-colour directives: $path"
                continue
            }
            try {
                Write-WatcherLog "Preview: $path"
                $output = Convert-ExportCopy $path $text $processor
                Write-WatcherLog "Created: $output"
                $tray.ShowBalloonTip(6000, 'Manual multicolor file ready', [IO.Path]::GetFileName($output), [Windows.Forms.ToolTipIcon]::Info)
            } catch {
                Write-WatcherLog "No output for ${path}: $($_.Exception.Message)"
                $tray.ShowBalloonTip(6000, 'Manual multicolor: no output written', $_.Exception.Message, [Windows.Forms.ToolTipIcon]::Warning)
            }
        }
    } catch { Write-WatcherLog "Watcher: $($_.Exception.Message)" }
    finally { $timer.Start() }
})
try {
    Write-WatcherLog "Started watching $Folder; existing files ignored"
    $tray.ShowBalloonTip(6000, 'Manual multicolor active', "Export new G-code to $Folder. Right-click this icon to stop.", [Windows.Forms.ToolTipIcon]::Info)
    $timer.Start()
    [Windows.Forms.Application]::Run($context)
} finally {
    $timer.Stop(); $timer.Dispose()
    $tray.Visible = $false; $tray.Dispose(); $menu.Dispose(); $context.Dispose()
    Write-WatcherLog 'Stopped'
    $mutex.ReleaseMutex(); $mutex.Dispose()
}
