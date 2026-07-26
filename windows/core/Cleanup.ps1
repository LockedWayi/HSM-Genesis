#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-BackupRetention {
    <#
    .SYNOPSIS
        Enforces a maximum backup count under the project's output\backups\
        directory. Keeps the N most recent backup files, deletes the rest.
        Called once at the start of each session from Start-GenesisEngine
        (wired in Prompt 5 — do not call it from here).

    .PARAMETER BackupDir
        Full path to the backup directory.
        Example: "C:\...\Genesis-Init\windows\output\backups"

    .PARAMETER MaxBackups
        Maximum number of backup files to keep. Default: 10.
        The N most recently LastWriteTime files are kept; all others deleted.

    .NOTES
        File pattern: hardserver.cfg.bak_*
        Match both RFS-side and client-side backups under the same directory.

        If BackupDir does not exist, log INFO "Backup directory not found,
        skipping retention." and return — do not create the directory here,
        that is done elsewhere when the first backup is written.

        If the number of matching files is <= MaxBackups, log INFO
        "Backup retention: <n> backups present, limit <MaxBackups>, nothing
        to remove." and return.

        For each file deleted, log INFO "Backup retention: removed <filename>".
        At the end, log INFO "Backup retention: kept <n> of <total> backups,
        removed <removed_count>."

        Never throw. If an individual file deletion fails (e.g. locked file),
        log WARN "Could not delete backup <filename>: <error>" and continue
        to the next file.

    .OUTPUTS
        None. All results communicated via Write-GenesisLog.
    #>
    param(
        [Parameter(Mandatory)] [string] $BackupDir,
        [int] $MaxBackups = 10
    )

    if (-not (Test-Path -LiteralPath $BackupDir -PathType Container)) {
        Write-GenesisLog -Level INFO -Message "Backup directory not found, skipping retention."
        return
    }

    $allBackups = @(Get-ChildItem -LiteralPath $BackupDir -Filter 'hardserver.cfg.bak_*' -File | Sort-Object LastWriteTime -Descending)
    $total = $allBackups.Count

    if ($total -le $MaxBackups) {
        Write-GenesisLog -Level INFO -Message "Backup retention: $total backups present, limit $MaxBackups, nothing to remove."
        return
    }

    $toRemove = $allBackups | Select-Object -Skip $MaxBackups
    $removedCount = 0

    foreach ($file in $toRemove) {
        try {
            Remove-Item -LiteralPath $file.FullName -Force -ErrorAction Stop
            Write-GenesisLog -Level INFO -Message "Backup retention: removed $($file.Name)"
            $removedCount++
        } catch {
            Write-GenesisLog -Level WARN -Message "Could not delete backup $($file.Name): $($_.Exception.Message)"
        }
    }

    $kept = $total - $removedCount
    Write-GenesisLog -Level INFO -Message "Backup retention: kept $kept of $total backups, removed $removedCount."
}

function Invoke-PushWorkdirCleanup {
    <#
    .SYNOPSIS
        Clears all files from the push staging directory
        (output\push-workdir\) before each cfg-pushnethsm call.
        Ensures stale config files from a previous run are never
        accidentally pushed.

    .PARAMETER PushWorkDir
        Full path to the staging directory.
        Example: "C:\...\Genesis-Init\windows\output\push-workdir"

    .NOTES
        If PushWorkDir does not exist, create it (New-Item -Force) and
        log INFO "Push workdir created: <path>". Return immediately after
        creation — nothing to clean.

        If it exists, delete all files directly inside it (non-recursive,
        no subdirectories — the workdir never contains subdirectories in
        normal operation).

        Log INFO "Push workdir cleared: <n> file(s) removed." after cleanup.

        Never throw. If an individual file deletion fails, log WARN and
        continue.

    .OUTPUTS
        None.
    #>
    param(
        [Parameter(Mandatory)] [string] $PushWorkDir
    )

    if (-not (Test-Path -LiteralPath $PushWorkDir -PathType Container)) {
        try {
            New-Item -Path $PushWorkDir -ItemType Directory -Force | Out-Null
        } catch {
            return _New-GenesisResult -Success $false `
                -ErrorMessage "Failed to create push workdir: $PushWorkDir" `
                -ErrorDetail $_.Exception.Message
        }
        Write-GenesisLog -Level INFO -Message "Push workdir created: $PushWorkDir"
        return
    }

    $files = @(Get-ChildItem -LiteralPath $PushWorkDir -File)
    $removedCount = 0

    foreach ($file in $files) {
        try {
            Remove-Item -LiteralPath $file.FullName -Force -ErrorAction Stop
            $removedCount++
        } catch {
            Write-GenesisLog -Level WARN -Message "Could not delete file $($file.Name) in push workdir: $($_.Exception.Message)"
        }
    }

    Write-GenesisLog -Level INFO -Message "Push workdir cleared: $removedCount file(s) removed."
}
