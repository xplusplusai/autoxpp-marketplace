# launch_vs.ps1 - ensure VS 2022 is running. Launch if not. Wait for MainWindowHandle.
#
# Usage: launch_vs.ps1 [-VsPath <path>] [-TimeoutSeconds 120]
# Emits:
#   VS_ALREADY_RUNNING pid=<n>
#   VS_LAUNCHED pid=<n>
#   VS_LAUNCH_TIMEOUT

param(
    [string]$VsPath = "",
    [int]$TimeoutSeconds = 120
)

function Find-VsProcess {
    # Prefer a process with a visible MainWindowHandle
    $procs = Get-Process devenv -ErrorAction SilentlyContinue
    if (-not $procs) { return $null }
    $withWindow = $procs | Where-Object { $_.MainWindowHandle -ne [IntPtr]::Zero } | Select-Object -First 1
    if ($withWindow) { return $withWindow }
    return ($procs | Select-Object -First 1)
}

$existing = Find-VsProcess
if ($existing -and $existing.MainWindowHandle -ne [IntPtr]::Zero) {
    Write-Host "VS_ALREADY_RUNNING pid=$($existing.Id)"
    exit 0
}

if (-not $VsPath) {
    # Try common install paths
    $candidates = @(
        "C:\Program Files\Microsoft Visual Studio\2022\Professional\Common7\IDE\devenv.exe",
        "C:\Program Files\Microsoft Visual Studio\2022\Enterprise\Common7\IDE\devenv.exe",
        "C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\devenv.exe"
    )
    foreach ($c in $candidates) { if (Test-Path $c) { $VsPath = $c; break } }
}

if (-not $VsPath -or -not (Test-Path $VsPath)) {
    Write-Host "ERROR: devenv.exe not found. Specify -VsPath or set vsPath in ude-configs.json defaults."
    exit 1
}

Write-Host "Launching VS: $VsPath"
$proc = Start-Process -FilePath $VsPath -PassThru

$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
while ((Get-Date) -lt $deadline) {
    Start-Sleep -Seconds 2
    $p = Find-VsProcess
    if ($p -and $p.MainWindowHandle -ne [IntPtr]::Zero) {
        Write-Host "VS_LAUNCHED pid=$($p.Id)"
        exit 0
    }
}

Write-Host "VS_LAUNCH_TIMEOUT waited=${TimeoutSeconds}s"
exit 1
