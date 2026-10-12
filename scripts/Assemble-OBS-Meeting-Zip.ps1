param(
    [Parameter(Mandatory=$true)][string]$SourceRoot,
    [Parameter(Mandatory=$true)][string]$BuilderRoot,
    [Parameter(Mandatory=$true)][string]$OutputRoot
)
$ErrorActionPreference = 'Stop'
$SourceRoot = [IO.Path]::GetFullPath($SourceRoot)
$BuilderRoot = [IO.Path]::GetFullPath($BuilderRoot)
$OutputRoot = [IO.Path]::GetFullPath($OutputRoot)
$build = Join-Path $SourceRoot 'build_x64'
$archives = @(Get-ChildItem -LiteralPath $build -Filter '*windows-x64.zip' -File -ErrorAction Stop)
if ($archives.Count -ne 1) { throw "Expected exactly one upstream Windows x64 ZIP; found $($archives.Count)" }
$work = Join-Path $env:RUNNER_TEMP 'OBSMeetingPortablePackage'
if (Test-Path -LiteralPath $work) { Remove-Item -LiteralPath $work -Recurse -Force }
New-Item -ItemType Directory -Path $work -Force | Out-Null
$extracted = Join-Path $work 'extracted'
Expand-Archive -LiteralPath $archives[0].FullName -DestinationPath $extracted -Force
$executables = @(Get-ChildItem -LiteralPath $extracted -Recurse -File -Filter 'obs64.exe')
$executables = @($executables | Where-Object { $_.Directory.Name -eq '64bit' -and $_.Directory.Parent.Name -eq 'bin' })
if ($executables.Count -ne 1) { throw 'Expected exactly one OBS bin\64bit\obs64.exe in release ZIP' }
$rootInZip = $executables[0].Directory.Parent.Parent.FullName
# OBS 33 (the inspected source revision) installs bundled modules under core/.
# The previous assembler incorrectly required OBS 32's obs-plugins/ folder.
# Accept either upstream layout, but validate actual meeting-recording modules.
Write-Host "Detected OBS archive root: $rootInZip"
Write-Host 'Top-level entries in the upstream archive:'
Get-ChildItem -LiteralPath $rootInZip -Force | ForEach-Object {
    Write-Host ("  {0} {1}" -f $(if ($_.PSIsContainer) { 'DIR ' } else { 'FILE' }), $_.Name)
}
$requiredData = @('data\libobs', 'data\obs-studio')
foreach ($relative in $requiredData) {
    $targetPath = Join-Path $rootInZip $relative
    if (-not (Test-Path -LiteralPath $targetPath -PathType Container)) {
        throw "Upstream OBS application data is missing: $relative. Do not package an incomplete build."
    }
}
$modernRequired = @(
    'core\win-capture\win-capture.dll',
    'core\win-wasapi\win-wasapi.dll',
    'core\obs-ffmpeg\obs-ffmpeg.dll',
    'core\obs-outputs\obs-outputs.dll'
)
$legacyRequired = @(
    'obs-plugins\64bit\win-capture.dll',
    'obs-plugins\64bit\win-wasapi.dll',
    'obs-plugins\64bit\obs-ffmpeg.dll',
    'obs-plugins\64bit\obs-outputs.dll'
)
$hasModernDirectory = Test-Path -LiteralPath (Join-Path $rootInZip 'core') -PathType Container
$hasLegacyDirectory = Test-Path -LiteralPath (Join-Path $rootInZip 'obs-plugins') -PathType Container
if ($hasModernDirectory -and $hasLegacyDirectory) {
    throw 'Upstream archive contains both core/ and obs-plugins/. Inspect the layout before repackaging.'
}
if ($hasModernDirectory) {
    $moduleLayout = 'OBS 33 bundled modules (core/)'
    $requiredModules = $modernRequired
} elseif ($hasLegacyDirectory) {
    $moduleLayout = 'OBS 32 legacy modules (obs-plugins/)'
    $requiredModules = $legacyRequired
} else {
    throw 'Upstream archive has neither core/ nor obs-plugins/. Its plugin layout is unrecognized.'
}
foreach ($relative in $requiredModules) {
    $moduleFile = Join-Path $rootInZip $relative
    if (-not (Test-Path -LiteralPath $moduleFile -PathType Leaf)) {
        throw "Required recording plugin is missing: $relative. The archive is incomplete or upstream layout changed."
    }
}
Write-Host "Recognized module layout: $moduleLayout"
Write-Host 'Validated Display/Window Capture, WASAPI, FFmpeg and output modules.'
if (Test-Path (Join-Path $rootInZip 'config\obs-studio')) {
    throw 'Upstream archive unexpectedly contains user profile config; refusing to package personal settings'
}
$stage = Join-Path $work 'OBS-Meeting-Portable-TEST'
New-Item -ItemType Directory -Path $stage -Force | Out-Null
Get-ChildItem -LiteralPath $rootInZip -Force | Copy-Item -Destination $stage -Recurse -Force
foreach ($relative in @('bin\64bit\obs64.exe', 'data\libobs') + $requiredModules) {
    if (-not (Test-Path -LiteralPath (Join-Path $stage $relative))) {
        throw "The staged OBS package is incomplete after copying: $relative"
    }
}
$cfg = Join-Path $stage 'config\obs-studio\shader-cache'
New-Item -ItemType Directory -Path $cfg -Force | Out-Null
'' | Set-Content -LiteralPath (Join-Path $stage 'portable_mode.txt') -Encoding ascii
Copy-Item -LiteralPath (Join-Path $BuilderRoot 'portable\LAUNCH-OBS-MEETING-PORTABLE.cmd') -Destination $stage -Force
Copy-Item -LiteralPath (Join-Path $BuilderRoot 'portable\VERIFY-OBS-MEETING-PORTABILITY.cmd') -Destination $stage -Force
Copy-Item -LiteralPath (Join-Path $BuilderRoot 'portable\VERIFY-OBS-MEETING-PORTABILITY.ps1') -Destination $stage -Force
$sha = (git -C $SourceRoot rev-parse HEAD).Trim()
@"
OBS Meeting Portable Experimental Build
Source commit: $sha

Start LAUNCH-OBS-MEETING-PORTABLE.cmd; do not use direct obs64.exe for this test.
Native OBS config: config\obs-studio\
Patched D3D11 shader-cache: config\obs-studio\shader-cache\
Game Capture startup/deployment is disabled; Display, Window and Audio Capture
must be tested, not assumed working.

The original OBS updater is disabled by launch arguments. Some upstream UI
updater code or external graphics drivers may still create traces.
DO NOT upload this experimental ZIP to public PortableApps or replace a working OBS.
DO NOT erase any existing ProgramData directories or registry entries.
"@ | Set-Content -LiteralPath (Join-Path $stage 'READ-ME-FIRST.txt') -Encoding UTF8
New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null
$short = $sha.Substring(0,[Math]::Min(12,$sha.Length))
$output = Join-Path $OutputRoot "OBS-Meeting-Portable-EXPERIMENTAL-Windows-x64-$short.zip"
Compress-Archive -LiteralPath $stage -DestinationPath $output -CompressionLevel Optimal -Force
Write-Host "Produced experimental ZIP: $output"
