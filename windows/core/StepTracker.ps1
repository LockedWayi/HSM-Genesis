#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$global:GenesisWorkflow = $null

function Initialize-Workflow {
    <#
    .SYNOPSIS
        Resets the global workflow tracker. Must be called once at the
        start of each Genesis-Init session (called from Start-GenesisEngine
        in Engine.ps1 — do not call it from here).
    #>
    $global:GenesisWorkflow = @{
        SessionStart = Get-Date
        Steps        = [System.Collections.Generic.List[PSCustomObject]]::new()
        CurrentStep  = $null
    }
}

function Start-GenesisStep {
    <#
    .SYNOPSIS
        Marks the beginning of a named workflow step and starts timing it.
        Writes a visual section header to the console via Write-GenesisSection
        (from Logger.ps1) and logs an INFO entry.

    .PARAMETER Name
        Short human-readable step name, e.g. "anonkneti", "RFS enrollment".
        This is what appears in the final summary table.

    .NOTES
        Sets $global:GenesisWorkflow.CurrentStep to a new object:
        @{
            Name      = $Name
            StartTime = Get-Date
            Status    = 'Running'
            Duration  = $null
            Error     = $null
        }
        Appends this object to $global:GenesisWorkflow.Steps so it can be
        mutated in place when Complete-GenesisStep is called.

        If $global:GenesisWorkflow is $null (Initialize-Workflow was never
        called), write an ERROR log and return without throwing.
    #>
    param(
        [Parameter(Mandatory)] [string] $Name
    )

    if ($null -eq $global:GenesisWorkflow) {
        Write-GenesisLog -Level ERROR -Message "Start-GenesisStep called but GenesisWorkflow is not initialized."
        return
    }

    Write-GenesisSection -Title $Name
    Write-GenesisLog -Level INFO -Message "Step started: $Name"

    $step = [PSCustomObject]@{
        Name      = $Name
        StartTime = Get-Date
        Status    = 'Running'
        Duration  = $null
        Error     = $null
    }

    $global:GenesisWorkflow.CurrentStep = $step
    $global:GenesisWorkflow.Steps.Add($step)
}

function Complete-GenesisStep {
    <#
    .SYNOPSIS
        Closes the current step, records its final status and duration.
        Writes an INFO log entry with duration.

    .PARAMETER Status
        One of: 'Success', 'Failed', 'Skipped', 'Warning'

    .PARAMETER ErrorMessage
        Optional. Human-readable failure description. Stored in the step
        object for display in Show-GenesisSummary. Only meaningful when
        Status is 'Failed'.

    .NOTES
        Calculates duration as (Get-Date) - CurrentStep.StartTime.
        Stores duration as a [TimeSpan] in the step object.
        Sets CurrentStep.Status and CurrentStep.Error.
        Sets $global:GenesisWorkflow.CurrentStep = $null after closing.

        If there is no CurrentStep ($global:GenesisWorkflow.CurrentStep is
        $null), write a WARN log "Complete-GenesisStep called with no active
        step" and return without throwing.
    #>
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Success', 'Failed', 'Skipped', 'Warning')]
        [string] $Status,

        [string] $ErrorMessage = $null
    )

    if ($null -eq $global:GenesisWorkflow -or $null -eq $global:GenesisWorkflow.CurrentStep) {
        Write-GenesisLog -Level WARN -Message "Complete-GenesisStep called with no active step."
        return
    }

    $step = $global:GenesisWorkflow.CurrentStep
    $duration = (Get-Date) - $step.StartTime

    $step.Status   = $Status
    $step.Duration = $duration
    if ($Status -eq 'Failed' -and $ErrorMessage) {
        $step.Error = $ErrorMessage
    }

    Write-GenesisLog -Level INFO -Message "Step completed: $($step.Name) | Status: $Status | Duration: $([math]::Round($duration.TotalSeconds, 1))s"

    $global:GenesisWorkflow.CurrentStep = $null
}

function _Format-Duration {
    param([TimeSpan]$ts)
    if ($ts.TotalSeconds -lt 60) {
        return "{0:N1}s" -f $ts.TotalSeconds
    } else {
        $mins = [math]::Floor($ts.TotalMinutes)
        $secs = $ts.Seconds
        return "${mins}m ${secs}s"
    }
}

function Show-GenesisSummary {
    <#
    .SYNOPSIS
        Prints a formatted summary table of all steps and the total session
        duration to the console. Also writes the full table to the log file
        via Write-GenesisLog at INFO level.
    #>
    if ($null -eq $global:GenesisWorkflow -or $global:GenesisWorkflow.Steps.Count -eq 0) {
        Write-GenesisLog -Level INFO -Message "No steps recorded in this session."
        return
    }

    $totalDuration = (Get-Date) - $global:GenesisWorkflow.SessionStart
    $totalDurationStr = _Format-Duration $totalDuration

    $border = '=' * 60
    Write-Host $border -ForegroundColor DarkGray
    Write-Host '  GENESIS-INIT SESSION SUMMARY' -ForegroundColor White
    Write-Host $border -ForegroundColor DarkGray
    Write-Host '  #   Step                     Duration   Status' -ForegroundColor DarkGray
    Write-Host '  -   ----                     --------   ------' -ForegroundColor DarkGray

    $logLines = [System.Collections.Generic.List[string]]::new()
    $logLines.Add($border)
    $logLines.Add('  GENESIS-INIT SESSION SUMMARY')
    $logLines.Add($border)
    $logLines.Add('  #   Step                     Duration   Status')
    $logLines.Add('  -   ----                     --------   ------')

    $failCount = 0
    $hasWarning = $false

    for ($i = 0; $i -lt $global:GenesisWorkflow.Steps.Count; $i++) {
        $step = $global:GenesisWorkflow.Steps[$i]
        
        $idxStr = ($i + 1).ToString().PadRight(3)
        $nameStr = $step.Name
        if ($nameStr.Length -gt 24) { $nameStr = $nameStr.Substring(0, 21) + '...' }
        $nameStr = $nameStr.PadRight(24)

        $durStr = if ($null -ne $step.Duration) { (_Format-Duration $step.Duration) } else { "-" }
        $durStr = $durStr.PadRight(10)

        $statusStr = ''
        $statusColor = 'White'
        
        switch ($step.Status) {
            'Success' { $statusStr = 'OK'; $statusColor = 'Green' }
            'Warning' { $statusStr = 'WARN'; $statusColor = 'Yellow'; $hasWarning = $true }
            'Skipped' { $statusStr = 'SKIP'; $statusColor = 'DarkGray' }
            'Failed'  { $statusStr = 'FAILED'; $statusColor = 'Red'; $failCount++ }
            default   { $statusStr = $step.Status; $statusColor = 'White' }
        }

        # console
        Write-Host ("  $idxStr $nameStr $durStr ") -NoNewline
        Write-Host $statusStr -ForegroundColor $statusColor

        # log line
        $logLines.Add("  $idxStr $nameStr $durStr $statusStr")
    }

    $resultText = ""
    $resultColor = 'White'
    
    if ($failCount -gt 0) {
        $plural = if ($failCount -gt 1) { 's' } else { '' }
        $resultText = "FAILED ($failCount step$plural failed)"
        $resultColor = 'Red'
    } elseif ($hasWarning) {
        $resultText = "COMPLETED WITH WARNINGS"
        $resultColor = 'Yellow'
    } else {
        $resultText = "SUCCESS"
        $resultColor = 'Green'
    }

    Write-Host $border -ForegroundColor DarkGray
    Write-Host "  Total session duration: $totalDurationStr" -ForegroundColor White
    Write-Host ("  Result: ") -NoNewline
    Write-Host $resultText -ForegroundColor $resultColor
    Write-Host $border -ForegroundColor DarkGray

    $logLines.Add($border)
    $logLines.Add("  Total session duration: $totalDurationStr")
    $logLines.Add("  Result: $resultText")
    $logLines.Add($border)

    $fullLog = $logLines -join "`r`n"
    Write-GenesisLog -Level INFO -Message "`r`n$fullLog" -NoConsole
}
