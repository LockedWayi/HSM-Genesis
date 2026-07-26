#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function _New-GenesisResult {
    param(
        [bool]   $Success,
        [int]    $ExitCode    = -1,
        $Data                 = $null,
        [string] $ErrorMessage = $null,
        [string] $ErrorDetail  = $null
    )
    return [PSCustomObject]@{
        Success      = $Success
        ExitCode     = $ExitCode
        Data         = $Data
        ErrorMessage = $ErrorMessage
        ErrorDetail  = $ErrorDetail
    }
}

function _Build-NethsmEntry {
    param(
        [Parameter(Mandatory)] [string] $RemoteIp,
        [Parameter(Mandatory)] [int]    $RemotePort,
        [string] $RemoteEsn             = '',
        [string] $Keyhash               = '0000000000000000000000000000000000000000',
        [int]    $LocalModule           = 0,
        [int]    $Privileged            = 0,
        [int]    $PrivilegedUseHighPort = 0,
        [string] $NtokenEsn             = ''
    )

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add("local_module=$LocalModule")
    $lines.Add("remote_ip=$RemoteIp")
    $lines.Add("remote_port=$RemotePort")
    if ($RemoteEsn)  { $lines.Add("remote_esn=$RemoteEsn") }
    $lines.Add("keyhash=$Keyhash")
    $lines.Add("privileged=$Privileged")
    $lines.Add("privileged_use_high_port=$PrivilegedUseHighPort")
    if ($NtokenEsn)  { $lines.Add("ntoken_esn=$NtokenEsn") }
    return ($lines -join "`r`n")
}

function _Build-NethsmDynamicBlock {
    param([PSCustomObject[]] $HsmEntries)

    $entries = foreach ($hsm in $HsmEntries) {
        _Build-NethsmEntry `
            -RemoteIp   $hsm.IP `
            -RemotePort 9004 `
            -RemoteEsn  $hsm.ESN `
            -Keyhash    $hsm.Keyhash `
            -Privileged $hsm.Privileged
    }
    return ($entries -join "`r`n-`r`n")
}

function _Test-EntrustConfigExists {
    param([Parameter(Mandatory)] [string] $ConfigPath)
    return (Test-Path -LiteralPath $ConfigPath -PathType Leaf)
}

function _Backup-EntrustConfig {
    param(
        [Parameter(Mandatory)] [string] $ConfigPath,
        [Parameter(Mandatory)] [string] $BackupDir
    )

    if (-not (Test-Path -LiteralPath $BackupDir)) {
        $null = New-Item -Path $BackupDir -ItemType Directory -Force
        Write-GenesisLog -Level INFO -Message "Backup directory created: $BackupDir"
    }

    $timestamp  = Get-Date -Format 'yyyyMMdd_HHmmss'
    $backupName = "hardserver.cfg.bak_$timestamp"
    $backupPath = Join-Path $BackupDir $backupName

    Copy-Item -LiteralPath $ConfigPath -Destination $backupPath -Force
    Write-GenesisLog -Level INFO -Message "Config backed up -> $backupPath"

    return $backupPath
}

# ============================================================
#  PUBLIC API
# ============================================================

function New-EntrustHardserverConfig {
    param(
        [Parameter(Mandatory)] [PSCustomObject[]] $HsmEntries,
        [Parameter(Mandatory)] [string]   $TemplatePath,
        [Parameter(Mandatory)] [string]   $OutputPath,
        [int]    $RemotePort = 9004,
        [string] $BackupDir  = '.\output\backups'
    )

    if (-not (Test-Path -LiteralPath $TemplatePath -PathType Leaf)) {
        Write-GenesisLog -Level ERROR -Message "Template not found: $TemplatePath"
        return _New-GenesisResult -Success $false -ErrorMessage "Template file missing: $TemplatePath"
    }

    if (_Test-EntrustConfigExists -ConfigPath $OutputPath) {
        Write-GenesisLog -Level WARN -Message "Existing hardserver config detected: $OutputPath"
        Write-Host ''
        Write-Host '[!] Existing hardserver.cfg found.' -ForegroundColor Yellow
        Write-Host "    Location : $OutputPath"            -ForegroundColor Yellow
        Write-Host '    If continued, it will be backed up and rewritten from scratch.' -ForegroundColor Yellow
        Write-Host ''

        $confirm = Read-ValidatedInput -Prompt 'Do you want to continue? (Y/N): ' -Validator { param($v) Test-GenesisYesNo -Value $v }

        if ($confirm -match '^(n|no)$') {
            Write-GenesisLog -Level INFO -Message 'User cancelled - config unmodified.'
            Write-Host '[i] Operation cancelled. Config file unmodified.' -ForegroundColor Cyan
            return _New-GenesisResult -Success $false -ErrorMessage "User declined overwrite"
        }

        try {
            $null = _Backup-EntrustConfig -ConfigPath $OutputPath -BackupDir $BackupDir
        } catch {
            return _New-GenesisResult -Success $false `
                -ErrorMessage "Failed to back up existing hardserver.cfg before write." `
                -ErrorDetail $_.Exception.Message
        }
    }

    $count = $HsmEntries.Count
    $ips = ($HsmEntries | ForEach-Object { $_.IP }) -join ', '
    Write-GenesisLog -Level INFO -Message "Generating nethsm_imports block for $count HSMs: $ips"

    $dynamicBlock = _Build-NethsmDynamicBlock -HsmEntries $HsmEntries

    try {
        $templateContent = Get-Content -LiteralPath $TemplatePath -Raw -Encoding ASCII
    } catch {
        return _New-GenesisResult -Success $false `
            -ErrorMessage "Failed to read hardserver.cfg template at: $TemplatePath" `
            -ErrorDetail $_.Exception.Message
    }

    if ($templateContent -notmatch '\{\{NETHSM_DYNAMIC_BLOCK\}\}') {
        Write-GenesisLog -Level ERROR -Message "Placeholder not found in template: $TemplatePath"
        return _New-GenesisResult -Success $false -ErrorMessage "Template is missing {{NETHSM_DYNAMIC_BLOCK}} placeholder."
    }

    $finalContent = $templateContent.Replace('{{NETHSM_DYNAMIC_BLOCK}}', $dynamicBlock)

    $outputDir = Split-Path -Parent $OutputPath
    if ($outputDir -and (-not (Test-Path -LiteralPath $outputDir))) {
        try {
            New-Item -Path $outputDir -ItemType Directory -Force | Out-Null
        } catch {
            return _New-GenesisResult -Success $false `
                -ErrorMessage "Failed to create output directory: $outputDir" `
                -ErrorDetail $_.Exception.Message
        }
        Write-GenesisLog -Level INFO -Message "Output directory created: $outputDir"
    }

    try {
        [System.IO.File]::WriteAllText(
            $OutputPath,
            $finalContent,
            [System.Text.Encoding]::ASCII
        )
    } catch {
        Write-GenesisLog -Level ERROR -Message "Failed to write config: $($_.Exception.Message)"
        return _New-GenesisResult -Success $false -ErrorMessage "Failed to write hardserver.cfg" -ErrorDetail $_.Exception.Message
    }

    $registeredIps = ($HsmEntries | ForEach-Object { $_.IP }) -join ' | '
    Write-GenesisLog -Level INFO  -Message "hardserver.cfg written: $OutputPath"
    Write-GenesisLog -Level INFO  -Message "Registered HSMs: $registeredIps"

    Write-Host ''
    Write-Host '[OK] hardserver.cfg successfully created.' -ForegroundColor Green
    Write-Host "     $count HSMs registered: $ips" -ForegroundColor Green
    Write-Host ''

    return _New-GenesisResult -Success $true -ExitCode 0 -Data @{ RegisteredIPs = @($HsmEntries | ForEach-Object { $_.IP }) }
}

function Add-HsClientEntry {
    param(
        [Parameter(Mandatory)] [string] $FilePath,
        [Parameter(Mandatory)] [string] $ClientIp,
        [Parameter(Mandatory)]
        [ValidateSet('priv','unpriv','priv_lowport')]
        [string] $ClientPerm,
        [string] $Keyhash = '0000000000000000000000000000000000000000',
        [string] $Esn     = ''
    )

    if (-not (Test-Path -LiteralPath $FilePath -PathType Leaf)) {
        Write-GenesisLog -Level ERROR -Message "HSM config file not found: $FilePath"
        return _New-GenesisResult -Success $false -ErrorMessage "Target config file does not exist: $FilePath"
    }

    try {
        $allLines = [System.IO.File]::ReadAllLines($FilePath, [System.Text.Encoding]::ASCII)
    } catch {
        return _New-GenesisResult -Success $false `
            -ErrorMessage "Failed to read hardserver.cfg at: $FilePath" `
            -ErrorDetail $_.Exception.Message
    }

    $sectionStart    = -1
    $sectionEnd      = $allLines.Count
    $hasEntries      = $false
    $lastDataLine    = -1

    for ($i = 0; $i -lt $allLines.Count; $i++) {
        $trimmed = $allLines[$i].Trim()

        if ($trimmed -eq '[hs_clients]') {
            $sectionStart = $i
            continue
        }

        if ($sectionStart -ge 0 -and $trimmed -match '^\[') {
            $sectionEnd = $i
            break
        }

        if ($sectionStart -ge 0) {
            if ($trimmed -ne '' -and -not $trimmed.StartsWith('#')) {
                $hasEntries = $true
                $lastDataLine = $i
            }
        }
    }

    if ($sectionStart -lt 0) {
        Write-GenesisLog -Level ERROR -Message "[hs_clients] section not found: $FilePath"
        return _New-GenesisResult -Success $false -ErrorMessage "[hs_clients] section not found in $FilePath"
    }

    $foundExisting = $false
    $existingPermLineIdx = -1
    $existingPermVal = $null

    for ($i = $sectionStart + 1; $i -lt $sectionEnd; $i++) {
        $trimmed = $allLines[$i].Trim()

        if ($trimmed -eq "addr=$ClientIp") {
            $foundExisting = $true
            for ($j = $i - 1; $j -gt $sectionStart; $j--) {
                if ($allLines[$j].Trim() -match '^\-+$' -or $allLines[$j].Trim() -eq '') { break }
                if ($allLines[$j].Trim() -match '^clientperm=(.+)$') {
                    $existingPermLineIdx = $j
                    $existingPermVal = $matches[1]
                    break
                }
            }
            if ($existingPermLineIdx -eq -1) {
                for ($j = $i + 1; $j -lt $sectionEnd; $j++) {
                    if ($allLines[$j].Trim() -match '^\-+$' -or $allLines[$j].Trim() -eq '') { break }
                    if ($allLines[$j].Trim() -match '^clientperm=(.+)$') {
                        $existingPermLineIdx = $j
                        $existingPermVal = $matches[1]
                        break
                    }
                }
            }
            break
        }
    }

    if ($foundExisting) {
        if ($existingPermVal -eq $ClientPerm) {
            Write-GenesisLog -Level INFO -Message "already registered, no change needed for $ClientIp"
            Write-Host "[i] Client already in hs_clients with requested permission ($ClientPerm): $ClientIp" -ForegroundColor Cyan
            return _New-GenesisResult -Success $true -ExitCode 0
        } else {
            Write-GenesisLog -Level WARN -Message "Client $ClientIp has clientperm='$existingPermVal' but requested='$ClientPerm'."

            $confirm = Read-ValidatedInput -Prompt "  Update $ClientIp clientperm from '$existingPermVal' to '$ClientPerm'? (Y/N): " -Validator { param($v) Test-GenesisYesNo -Value $v }

            if ($confirm -match '^(y|yes)$') {
                $output = [System.Collections.Generic.List[string]]::new()
                for ($i = 0; $i -lt $allLines.Count; $i++) {
                    if ($i -eq $existingPermLineIdx) {
                        $output.Add("clientperm=$ClientPerm")
                    } else {
                        $output.Add($allLines[$i])
                        if ($existingPermLineIdx -eq -1 -and $allLines[$i].Trim() -eq "addr=$ClientIp") {
                            $output.Add("clientperm=$ClientPerm")
                        }
                    }
                }

                try {
                    [System.IO.File]::WriteAllLines($FilePath, $output, [System.Text.Encoding]::ASCII)
                    Write-GenesisLog -Level INFO -Message "Updated clientperm for $ClientIp to $ClientPerm in $FilePath"
                    return _New-GenesisResult -Success $true -ExitCode 0
                } catch {
                    return _New-GenesisResult -Success $false -ErrorMessage "Failed to overwrite updated config file." -ErrorDetail $_.Exception.Message
                }
            } else {
                Write-GenesisLog -Level INFO -Message "kept as-is for $ClientIp"
                return _New-GenesisResult -Success $true -ExitCode 0
            }
        }
    }

    $newEntryLines = @(
        "addr=$ClientIp",
        "clientperm=$ClientPerm",
        "keyhash=$Keyhash",
        "esn=$Esn"
    )

    $insertAfter = if ($lastDataLine -ge 0) { $lastDataLine } else { $sectionStart }

    $output = [System.Collections.Generic.List[string]]::new()
    for ($i = 0; $i -le $insertAfter; $i++) {
        $output.Add($allLines[$i])
    }
    if ($hasEntries) {
        $output.Add('-----')
    }
    foreach ($line in $newEntryLines) {
        $output.Add($line)
    }
    for ($i = $insertAfter + 1; $i -lt $allLines.Count; $i++) {
        $output.Add($allLines[$i])
    }

    try {
        [System.IO.File]::WriteAllLines(
            $FilePath,
            $output,
            [System.Text.Encoding]::ASCII
        )
    } catch {
        return _New-GenesisResult -Success $false -ErrorMessage "Failed to write hs_clients append" -ErrorDetail $_.Exception.Message
    }

    Write-GenesisLog -Level INFO -Message "Added to hs_clients: $ClientIp -> $FilePath"
    return _New-GenesisResult -Success $true -ExitCode 0
}