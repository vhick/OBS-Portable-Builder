$ErrorActionPreference='Stop'
$root=$PSScriptRoot
$logDir=Join-Path $root 'Verification'
New-Item -ItemType Directory -Path $logDir -Force | Out-Null
$report=Join-Path $logDir ('OBS-Meeting-Verification-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'.txt')
$lines=New-Object System.Collections.Generic.List[string]
function Record([string]$s){Write-Host $s;[void]$lines.Add($s)}
function Snapshot([string]$point){
    Record "== $point =="
    foreach($dir in @((Join-Path $env:ProgramData 'obs-studio-hook'),(Join-Path $env:ProgramData 'obs-studio\shader-cache'),(Join-Path $env:APPDATA 'obs-studio'),(Join-Path $root 'config\obs-studio\shader-cache'),(Join-Path $root 'config\obs-studio\basic\scenes'))){
        Record ("Path: {0} exists={1}" -f $dir,(Test-Path -LiteralPath $dir))
        if(Test-Path -LiteralPath $dir -PathType Container){
            Get-ChildItem -LiteralPath $dir -Force -ErrorAction SilentlyContinue | Select-Object -First 12 | ForEach-Object {Record ('  '+$_.Name+' modified='+$_.LastWriteTime.ToString('o'))}
        }
    }
}
Record 'EXPERIMENTAL OBS MEETING PORTABLE RUNTIME CHECK'
Record ('Generated '+(Get-Date -Format 'o'))
Record ('Portable application root '+$root)
if(Get-Process -Name obs64 -ErrorAction SilentlyContinue){
    Record 'ERROR: close all OBS processes in Task Manager before using this test.'
    $lines | Set-Content -LiteralPath $report -Encoding UTF8
    exit 1
}
Snapshot 'BEFORE launch'
Record 'Do not delete ProgramData directories: other OBS installations may use them.'
Record 'Now open LAUNCH-OBS-MEETING-PORTABLE.cmd, test screen/window/audio recording and save a short MKV.'
Read-Host 'When OBS is running, press Enter' | Out-Null
Snapshot 'WHILE running'
Read-Host 'Close OBS normally and press Enter' | Out-Null
Snapshot 'AFTER exit'
Record 'This check detects folder presence; creation by OBS vs leftover requires Process Monitor.'
Record 'No registry key is changed or deleted by this checker.'
$lines | Set-Content -LiteralPath $report -Encoding UTF8
Record ('Report saved: '+$report)
