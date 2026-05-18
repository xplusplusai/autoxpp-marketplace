# wait_for_validation.ps1 - wait while Power Platform Tools shows any of:
#   "Validating connection to Microsoft Dataverse..."
#   "Loading Workflows and Plugin Information - Loading Messages..."
#   "Loading Workflows and Plugin Information - Loading Steps..."
# Returns when the Select Solution dialog appears (or MFA/account picker surfaces).
#
# Usage: wait_for_validation.ps1 [-TimeoutSeconds 180]
#
# Emits:
#   VALIDATION_DONE (Select Solution visible)
#   VALIDATION_STUCK <lastMessage>
#   MFA_REQUIRED <dialogName>

param([int]$TimeoutSeconds = 180)

. "$PSScriptRoot\uia_helpers.ps1"

$vs = Get-VsProcess
if (-not $vs) { Write-Host "VALIDATION_ERROR VS not running"; exit 1 }

$vsElem = Get-VsAutomationElement -VsPid $vs.Id

$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
$lastSeen = ""
while ((Get-Date) -lt $deadline) {
    # Select Solution dialog means we're done
    $ss = Find-ChildWindow -Parent $vsElem -NameContains @('Select Solution')
    if ($ss) { Write-Host "VALIDATION_DONE"; exit 0 }

    # Account picker (cross-tenant) surfaces if multiple accounts
    $picker = Find-ChildWindow -Parent $vsElem -NameContains @('Sign in','Pick an account','choose an account')
    if ($picker) { Write-Host "MFA_REQUIRED name=$($picker.Current.Name)"; exit 2 }

    # Continue waiting — capture current Power Platform Tools dialog text for diagnostics
    $ppt = Find-ChildWindow -Parent $vsElem -NameContains @('Power Platform Tools','Connect to Dataverse')
    if ($ppt) {
        # Read any text descendants to report progress
        $textCond = New-Object System.Windows.Automation.PropertyCondition(
            [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
            [System.Windows.Automation.ControlType]::Text)
        $texts = $ppt.FindAll([System.Windows.Automation.TreeScope]::Descendants, $textCond)
        foreach ($t in $texts) {
            $nm = $t.Current.Name
            if ($nm -and ($nm -match 'Loading|Validating')) {
                if ($nm -ne $lastSeen) {
                    Write-Host "  $nm"
                    $lastSeen = $nm
                }
            }
        }
    }
    Start-Sleep -Seconds 2
}

Write-Host "VALIDATION_STUCK last=$lastSeen"
exit 1
