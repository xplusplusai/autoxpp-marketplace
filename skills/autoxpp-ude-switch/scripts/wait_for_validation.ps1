# wait_for_validation.ps1 - after the URL is submitted, wait while Power Platform Tools
# validates the connection and loads workflows/plugins, and return when step 2
# (Select Solution) becomes available.
#
# P-7 fix: completion is detected by the presence of the Select Solution control
# (AutomationId 'AccSolutionSelection', or a solutions ComboBox) inside the
# "Configure Microsoft Power Platform Solution" wizard - not by a window-name change
# (the wizard keeps the same title across steps). The old text-only poll reported a
# false VALIDATION_STUCK even though validation had finished.
#
# Usage: wait_for_validation.ps1 [-TimeoutSeconds 300]
#
# Emits:
#   VALIDATION_DONE      (Select Solution step available)
#   VALIDATION_STUCK     (timed out)

param([int]$TimeoutSeconds = 300)

. "$PSScriptRoot\uia_helpers.ps1"

$vs = Get-VsProcess
if (-not $vs) { Write-Output "VALIDATION_ERROR VS not running"; exit 1 }

$CT = [System.Windows.Automation.ControlType]
$TS = [System.Windows.Automation.TreeScope]

$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
$lastSeen = ""
while ((Get-Date) -lt $deadline) {
    $wizard = Find-AnyWindow -NameContains @(
        'Configure Microsoft Power Platform Solution',
        'Configure Power Platform Solution',
        'Power Platform Tools',
        'Connect to Dataverse')

    if ($wizard) {
        # Step 2 present? Prefer the AccSolutionSelection group; fall back to a ComboBox.
        $ss = Find-ByAutomationId -Parent $wizard -AutomationId 'AccSolutionSelection'
        if (-not $ss) {
            $comboCond = New-Object System.Windows.Automation.PropertyCondition(
                [System.Windows.Automation.AutomationElement]::ControlTypeProperty, $CT::ComboBox)
            $ss = $wizard.FindFirst($TS::Descendants, $comboCond)
        }
        if ($ss) { Write-Output "VALIDATION_DONE"; exit 0 }

        # Progress text (diagnostics)
        $textCond = New-Object System.Windows.Automation.PropertyCondition(
            [System.Windows.Automation.AutomationElement]::ControlTypeProperty, $CT::Text)
        foreach ($t in $wizard.FindAll($TS::Descendants, $textCond)) {
            $nm = $t.Current.Name
            if ($nm -and ($nm -match 'Loading|Validating') -and $nm -ne $lastSeen) {
                Write-Output "  $nm"; $lastSeen = $nm
            }
        }
    }

    Start-Sleep -Seconds 2
}

Write-Output "VALIDATION_STUCK last=$lastSeen"
exit 1
