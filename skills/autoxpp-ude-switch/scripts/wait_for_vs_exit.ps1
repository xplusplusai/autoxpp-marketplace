# wait_for_vs_exit.ps1 - poll VS until it exits (observed behavior: VS auto-closes after
# "Client assets download" completes on a new platform version so the F&O extension can
# register). If it does not exit within TimeoutSeconds, we return "still running" and
# the caller can proceed; otherwise we return "exited" and the caller relaunches.
#
# Usage: wait_for_vs_exit.ps1 [-Pid <vsPid>] [-TimeoutSeconds 3600]
# Emits:
#   VS_EXITED pid=<n>
#   VS_STILL_RUNNING pid=<n>

param(
    [int]$VsPid = 0,
    [int]$TimeoutSeconds = 3600
)

if ($VsPid -eq 0) {
    $p = Get-Process devenv -ErrorAction SilentlyContinue |
        Where-Object { $_.MainWindowHandle -ne [IntPtr]::Zero } | Select-Object -First 1
    if (-not $p) {
        Write-Host "VS_NOT_RUNNING (nothing to wait for)"
        exit 0
    }
    $VsPid = $p.Id
}

Write-Host "Waiting for VS (pid=$VsPid) to exit — up to ${TimeoutSeconds}s"
$deadline = (Get-Date).AddSeconds($TimeoutSeconds)

while ((Get-Date) -lt $deadline) {
    Start-Sleep -Seconds 5
    $p = Get-Process -Id $VsPid -ErrorAction SilentlyContinue
    if (-not $p) {
        Write-Host "VS_EXITED pid=$VsPid"
        exit 0
    }
}

Write-Host "VS_STILL_RUNNING pid=$VsPid"
exit 0
