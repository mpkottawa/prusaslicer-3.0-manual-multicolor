[CmdletBinding()]
param(
    [string]$SlicerPath,
    [string]$Folder,
    [switch]$CheckOnly
)
$ErrorActionPreference = 'Stop'
$Host.UI.RawUI.WindowTitle = 'PS3 Manual Multicolor - workflow console'
try {
    $settingsPath = Join-Path (Split-Path $PSScriptRoot) 'settings.json'
    $settings = Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json
    if (-not $SlicerPath) { $SlicerPath = $settings.slicer_path }
    if (-not $Folder) { $Folder = $settings.export_folder }
    if ([string]::IsNullOrWhiteSpace($SlicerPath) -or [string]::IsNullOrWhiteSpace($Folder)) {
        throw 'Set slicer_path and export_folder in settings.json.'
    }
    $SlicerPath = [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($SlicerPath))
    $Folder = [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($Folder))
    $watcher = Join-Path $PSScriptRoot '..\plugins\com.amade.manual-multicolor\postprocess\Watch-ManualMulticolor.ps1'
    $logPath = Join-Path $env:LOCALAPPDATA 'PrusaManualMulticolor\watcher.log'
    foreach ($required in @($SlicerPath, $watcher)) {
        if (-not (Test-Path -LiteralPath $required)) { throw "Required path missing: $required" }
    }
    if ($CheckOnly) {
        Write-Host "Configuration OK. Slicer: $SlicerPath; export folder: $Folder"
        Write-Host 'No applications started and no files changed.'
        return
    }
    [void][IO.Directory]::CreateDirectory($Folder)
    Write-Host 'PS3 MANUAL MULTICOLOR' -ForegroundColor Cyan
    Write-Host "Export folder: $Folder"
    Write-Host "Log: $logPath"
    Write-Host 'Select your manual multicolor profile. Export AFTER the watcher starts.'
    Write-Host 'The preview asks for confirmation. Upload only the resulting -manual.gcode.'
    $slicerRunning = @(Get-Process -Name PrusaSlicer -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $SlicerPath })
    if ($slicerRunning.Count) {
        Write-Host 'PS3 is already open; keeping that session and its unsaved project.' -ForegroundColor Green
    } else {
        Start-Process -FilePath $SlicerPath -WindowStyle Normal | Out-Null
        Write-Host 'PS3 launch requested.' -ForegroundColor Green
    }
    $existing = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object {
        $_.CommandLine -match '(?i)-File\s+"?[^"\r\n]*Watch-ManualMulticolor\.ps1' -and
        $_.CommandLine -like "*$Folder*"
    })
    if ($existing.Count) {
        Write-Host "Existing watcher process: $($existing[0].ProcessId). Showing its log; no duplicate started." -ForegroundColor Yellow
        Write-Host 'A process alone does not confirm readiness. Look for Started watching below.'
        Write-Host 'Closing this console does not stop that existing watcher.'
        if (Test-Path -LiteralPath $logPath) { Get-Content -LiteralPath $logPath -Tail 6 }
        $lastLength = if (Test-Path -LiteralPath $logPath) { (Get-Item -LiteralPath $logPath).Length } else { 0 }
        while (Get-Process -Id $existing[0].ProcessId -ErrorAction SilentlyContinue) {
            Start-Sleep -Seconds 2
            if (Test-Path -LiteralPath $logPath) {
                $stream = [IO.File]::Open($logPath, 'Open', 'Read', 'ReadWrite')
                try {
                    if ($stream.Length -lt $lastLength) { $lastLength = 0 }
                    [void]$stream.Seek($lastLength, 'Begin')
                    $reader = [IO.StreamReader]::new($stream)
                    try { $newText = $reader.ReadToEnd(); $lastLength = $stream.Position } finally { $reader.Dispose() }
                    if ($newText) { Write-Host $newText -NoNewline }
                } finally { $stream.Dispose() }
            }
        }
        Write-Host 'WATCHER STOPPED. Run this launcher again before exporting.' -ForegroundColor Red
    } else {
        Write-Host 'Starting watcher here. Keep this console open (you can minimize it).' -ForegroundColor Yellow
        & $watcher -Folder $Folder
        Write-Host 'Watcher stopped. Run this launcher again before exporting.' -ForegroundColor Yellow
    }
} catch {
    Write-Host "STARTUP FAILED: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace
    Write-Host 'Keep this window open and share the error text. No print was started.'
    exit 1
}
