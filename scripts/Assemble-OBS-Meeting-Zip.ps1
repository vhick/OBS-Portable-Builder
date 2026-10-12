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
if (-not (Test-Path (Join-Path $rootInZip 'data')) -or -not (Test-Path (Join-Path $rootInZip 'obs-plugins'))) {
    throw 'Upstream ZIP is missing required OBS data or plugins directories'
}
if (Test-Path (Join-Path $rootInZip 'config\obs-studio')) {
    throw 'Upstream archive unexpectedly contains user profile config; refusing to package personal settings'
}
$stage = Join-Path $work 'OBS-Meeting-Portable-TEST'
New-Item -ItemType Directory -Path $stage -Force | Out-Null
Get-ChildItem -LiteralPath $rootInZip -Force | Copy-Item -Destination $stage -Recurse -Force
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
