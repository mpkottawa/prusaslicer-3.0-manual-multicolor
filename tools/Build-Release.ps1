[CmdletBinding()]
param([string]$OutputDirectory)
$ErrorActionPreference = 'Stop'
$releaseRoot = Split-Path $PSScriptRoot
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $releaseRoot 'dist' }
$release = Get-Content -LiteralPath (Join-Path $releaseRoot 'release.json') -Raw | ConvertFrom-Json
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
[void][IO.Directory]::CreateDirectory($OutputDirectory)
$stem = 'PS3-Manual-Multicolor-' + $release.version + '-All-in-One'
$zipPath = Join-Path $OutputDirectory ($stem + '.zip')
if (Test-Path -LiteralPath $zipPath) { throw "Refusing to replace an existing release: $zipPath" }
& python (Join-Path $releaseRoot 'tests\validate_release.py')
if ($LASTEXITCODE -ne 0) { throw 'Release metadata checks failed.' }
$stageParent = Join-Path ([IO.Path]::GetTempPath()) ('ps3-release-' + [guid]::NewGuid().ToString('N'))
$stage = Join-Path $stageParent $stem
[void][IO.Directory]::CreateDirectory($stage)
$topFiles = @('README.md','LICENSE','THIRD_PARTY_NOTICES.md','CHANGELOG.md',
    'release.json','settings.json','start-auto-multicolor.cmd','quick-colors.cmd','install-ps3-tools.cmd','.gitignore')
foreach ($name in $topFiles) {
    Copy-Item -LiteralPath (Join-Path $releaseRoot $name) -Destination $stage
}
$extensions = @('.ps1','.cmd','.py','.js','.css','.jinja2','.json','.yaml','.lua','.md','.txt','.in','.gcode')
foreach ($name in @('plugins','tools','tests','presets','docs','licenses','octoprint-manual-multicolor')) {
    $source = Join-Path $releaseRoot $name
    foreach ($file in Get-ChildItem -LiteralPath $source -Recurse -File) {
        $relative = $file.FullName.Substring($releaseRoot.Length).TrimStart('\')
        if ($relative -match '(^|\\)(__pycache__|dist|build|[^\\]+\.egg-info)(\\|$)') { continue }
        if ($file.Extension -notin $extensions -and $file.Name -ne 'LICENSE') { continue }
        $destination = Join-Path $stage $relative
        [void][IO.Directory]::CreateDirectory((Split-Path $destination))
        Copy-Item -LiteralPath $file.FullName -Destination $destination
    }
}
$octoDist = Join-Path $stage 'octoprint'
[void][IO.Directory]::CreateDirectory($octoDist)
Push-Location (Join-Path $stage 'octoprint-manual-multicolor')
try {
    & python setup.py egg_info --egg-base $stageParent sdist --formats=zip --dist-dir $octoDist
    if ($LASTEXITCODE -ne 0) { throw 'OctoPrint ZIP build failed.' }
} finally { Pop-Location }
$octoZip = Join-Path $octoDist ('OctoPrint-manual_multicolor_ps3-' + $release.octoprint_version + '.zip')
if (-not (Test-Path -LiteralPath $octoZip)) { throw "Missing companion ZIP: $octoZip" }
$checksumLines = foreach ($file in Get-ChildItem -LiteralPath $stage -Recurse -File | Sort-Object FullName) {
    $relative = $file.FullName.Substring($stage.Length).TrimStart('\').Replace('\','/')
    '{0}  {1}' -f (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant(), $relative
}
[IO.File]::WriteAllLines((Join-Path $stage 'CHECKSUMS.sha256'), $checksumLines, [Text.UTF8Encoding]::new($false))
Add-Type -AssemblyName System.IO.Compression.FileSystem
[IO.Compression.ZipFile]::CreateFromDirectory($stage, $zipPath, [IO.Compression.CompressionLevel]::Optimal, $true)
$zipHash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
[IO.File]::WriteAllText((Join-Path $OutputDirectory 'SHA256SUMS.txt'), ($zipHash + '  ' + [IO.Path]::GetFileName($zipPath) + "`n"), [Text.UTF8Encoding]::new($false))
& python (Join-Path $releaseRoot 'tests\validate_release.py') --archive $zipPath
if ($LASTEXITCODE -ne 0) { throw 'Built archive failed validation; do not publish it.' }
Write-Host "Release created: $zipPath"
Write-Host "SHA256: $zipHash"
Write-Host "Build staging retained for inspection: $stage"
