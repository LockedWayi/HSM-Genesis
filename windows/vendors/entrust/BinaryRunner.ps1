#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$global:GenesisNfastHome = if ($env:NFAST_HOME) {
    $env:NFAST_HOME
} else {
    'C:\Program Files\nCipher\nfast'
}

$global:GenesisNfastBinPath    = Join-Path $global:GenesisNfastHome 'bin'
$global:GenesisNfastKmDataPath = if ($env:NFAST_KMDATA) {
    $env:NFAST_KMDATA
} else {
    'C:\ProgramData\nCipher\Key Management Data'
}

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

function _Invoke-NfastBinary {
    param(
        [Parameter(Mandatory)] [string]   $BinaryName,
        [string[]] $Arguments = @(),
        [switch] $Interactive,
        [switch] $TeeToConsole
    )

    $binaryPath = Join-Path $global:GenesisNfastBinPath $BinaryName

    if (-not (Test-Path -LiteralPath $binaryPath -PathType Leaf)) {
        Write-GenesisLog -Level ERROR -Message "Binary not found: $binaryPath"
        return [PSCustomObject]@{
            Success  = $false
            ExitCode = -1
            StdOut   = $null
            StdErr   = "Binary missing: $binaryPath"
            Error    = "Binary missing: $binaryPath"
        }
    }

    $stdoutTmp = [System.IO.Path]::GetTempFileName()
    $stderrTmp = [System.IO.Path]::GetTempFileName()

    Write-GenesisLog -Level DEBUG -Message "Running: $BinaryName $($Arguments -join ' ')"

    $proc = $null
    $stdoutText = ""
    $stderrText = ""
    $errMessage = ""

    try {
        $procParams = @{
            FilePath               = $binaryPath
            Wait                   = $true
            NoNewWindow            = $true
            PassThru               = $true
        }

        if (-not $Interactive) {
            $procParams['RedirectStandardOutput'] = $stdoutTmp
            $procParams['RedirectStandardError']  = $stderrTmp
        }

        if ($Arguments.Count -gt 0) {
            $procParams['ArgumentList'] = $Arguments
        }

        $proc = Start-Process @procParams

        if (-not $Interactive) {
            $stdoutText = Get-Content -LiteralPath $stdoutTmp -Raw -Encoding ASCII -ErrorAction SilentlyContinue
            $stderrText = Get-Content -LiteralPath $stderrTmp -Raw -Encoding ASCII -ErrorAction SilentlyContinue

            if ($stdoutText) {
                Write-GenesisLog -Level DEBUG -Message "[STDOUT] $($stdoutText.Trim())" -NoConsole
                if ($TeeToConsole) { Write-Host $stdoutText }
            }
            if ($stderrText) {
                Write-GenesisLog -Level DEBUG -Message "[STDERR] $($stderrText.Trim())" -NoConsole
            }
        }
    } catch {
        $errMessage = $_.Exception.Message
        Write-GenesisLog -Level ERROR -Message "Start-Process failed: $errMessage"
    } finally {
        Remove-Item -LiteralPath $stdoutTmp -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $stderrTmp -Force -ErrorAction SilentlyContinue
    }

    $success = $false
    $exitCode = -1
    if ($proc) {
        $exitCode = $proc.ExitCode
        $success = ($exitCode -eq 0)
    }

    return [PSCustomObject]@{
        Success  = $success
        ExitCode = $exitCode
        StdOut   = $stdoutText
        StdErr   = $stderrText
        Error    = $errMessage
    }
}

function Invoke-Anonkneti {
    param([Parameter(Mandatory)] [string] $HsmIp)

    Write-GenesisLog -Level INFO -Message "anonkneti.exe $HsmIp"

    $result = _Invoke-NfastBinary -BinaryName 'anonkneti.exe' -Arguments @($HsmIp)

    if (-not $result.Success) {
        Write-GenesisLog -Level ERROR -Message "anonkneti failed. ExitCode=$($result.ExitCode)"
        return _New-GenesisResult -Success $false -ExitCode $result.ExitCode -ErrorMessage "anonkneti execution failed for $HsmIp (ExitCode $($result.ExitCode))." -ErrorDetail $result.StdErr
    }

    $esnMatch = [regex]::Match($result.StdOut, '([0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4})')
    $keyhashMatch = [regex]::Match($result.StdOut, '([0-9A-Fa-f]{40})')

    if (-not $esnMatch.Success -or -not $keyhashMatch.Success) {
        Write-GenesisLog -Level ERROR -Message "Failed to parse anonkneti output."
        return _New-GenesisResult -Success $false -ExitCode $result.ExitCode -ErrorMessage "Failed to parse ESN or Keyhash from anonkneti output for $HsmIp." -ErrorDetail $result.StdOut
    }

    $esn = $esnMatch.Groups[1].Value.ToUpper()
    $keyhash = $keyhashMatch.Groups[1].Value.ToLower()

    Write-GenesisLog -Level INFO -Message "ESN detected     : $esn"
    Write-GenesisLog -Level INFO -Message "Keyhash detected : $keyhash"

    return _New-GenesisResult -Success $true -ExitCode $result.ExitCode -Data @{
        ESN       = $esn
        Keyhash   = $keyhash
    }
}

function Invoke-RfsSetupEnroll {
    param(
        [Parameter(Mandatory)] [string] $HsmIp,
        [Parameter(Mandatory)] [string] $Esn,
        [Parameter(Mandatory)] [string] $Keyhash
    )

    Write-GenesisSection -Title "rfs-setup - HSM Enrollment ($HsmIp)"
    Write-GenesisLog -Level INFO -Message "rfs-setup --force $HsmIp $Esn [keyhash]"

    $result = _Invoke-NfastBinary -BinaryName 'rfs-setup.exe' -Arguments @('--force', $HsmIp, $Esn, $Keyhash)

    if (-not $result.Success) {
        Write-GenesisLog -Level ERROR -Message "rfs-setup enrollment failed. ExitCode=$($result.ExitCode)"
        return _New-GenesisResult -Success $false -ExitCode $result.ExitCode -ErrorMessage "rfs-setup --force failed (ExitCode $($result.ExitCode))." -ErrorDetail $result.StdErr
    }

    Write-GenesisLog -Level INFO -Message "RFS enrollment completed: $HsmIp ($Esn)"
    return _New-GenesisResult -Success $true -ExitCode $result.ExitCode
}

function Invoke-RfsSetupGangClient {
    param([Parameter(Mandatory)] [string] $ClientIp)

    Write-GenesisLog -Level INFO -Message "rfs-setup --gang-client --write-noauth $ClientIp"

    $result = _Invoke-NfastBinary -BinaryName 'rfs-setup.exe' -Arguments @('--gang-client', '--write-noauth', $ClientIp)

    if (-not $result.Success) {
        Write-GenesisLog -Level ERROR -Message "Gang-client whitelist failed: $ClientIp | ExitCode=$($result.ExitCode)"
        return _New-GenesisResult -Success $false -ExitCode $result.ExitCode -ErrorMessage "rfs-setup --gang-client failed: $ClientIp (ExitCode $($result.ExitCode))." -ErrorDetail $result.StdErr
    }

    Write-GenesisLog -Level INFO -Message "Client added to whitelist: $ClientIp"
    return _New-GenesisResult -Success $true -ExitCode $result.ExitCode
}

function Invoke-CfgPushNethsm {
    param(
        [Parameter(Mandatory)] [string] $HsmIp,
        [Parameter(Mandatory)] [string] $ConfigPath
    )

    Write-GenesisSection -Title "cfg-pushnethsm - Config Push ($HsmIp)"

    if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
        Write-GenesisLog -Level ERROR -Message "Config to push not found: $ConfigPath"
        return _New-GenesisResult -Success $false -ExitCode -1 -ErrorMessage "cfg-pushnethsm config missing: $ConfigPath" -ErrorDetail "Config file not found"
    }

    Write-GenesisLog -Level INFO -Message "cfg-pushnethsm.exe -a $HsmIp `"$ConfigPath`""

    $result = _Invoke-NfastBinary -BinaryName 'cfg-pushnethsm.exe' -Arguments @('-a', $HsmIp, "`"$ConfigPath`"")

    if (-not $result.Success) {
        Write-GenesisLog -Level ERROR -Message "cfg-pushnethsm failed. ExitCode=$($result.ExitCode)"
        return _New-GenesisResult -Success $false -ExitCode $result.ExitCode -ErrorMessage "cfg-pushnethsm failed (ExitCode $($result.ExitCode))." -ErrorDetail $result.StdErr
    }

    Write-GenesisLog -Level INFO -Message "Config successfully pushed: $HsmIp"
    return _New-GenesisResult -Success $true -ExitCode $result.ExitCode
}

function Invoke-NethsmEnroll {
    param([Parameter(Mandatory)] [string] $HsmIp)

    Write-GenesisSection -Title "nethsmenroll - Client Enrollment ($HsmIp)"
    Write-GenesisLog -Level INFO -Message "nethsmenroll.exe --force $HsmIp"
    Write-Host "[i] nethsmenroll will run in interactive mode. Follow the on-screen instructions." -ForegroundColor Cyan

    $result = _Invoke-NfastBinary -BinaryName 'nethsmenroll.exe' -Arguments @('--force', $HsmIp) -Interactive

    if (-not $result.Success) {
        Write-GenesisLog -Level ERROR -Message "nethsmenroll failed. ExitCode=$($result.ExitCode)"
        return _New-GenesisResult -Success $false -ExitCode $result.ExitCode -ErrorMessage "nethsmenroll.exe failed (ExitCode $($result.ExitCode)). See console output." -ErrorDetail "Interactive output"
    }

    Write-GenesisLog -Level INFO -Message "HSM enrollment completed: $HsmIp"
    return _New-GenesisResult -Success $true -ExitCode $result.ExitCode
}

function Invoke-RfsSyncSetup {
    param([Parameter(Mandatory)] [string] $RfsIp)

    Write-GenesisSection -Title "rfs-sync - Setup ($RfsIp)"
    Write-GenesisLog -Level INFO -Message "rfs-sync.exe --setup --no-authenticate $RfsIp"

    $result = _Invoke-NfastBinary -BinaryName 'rfs-sync.exe' -Arguments @('--setup', '--no-authenticate', $RfsIp)

    if (-not $result.Success) {
        Write-GenesisLog -Level ERROR -Message "rfs-sync --setup failed. ExitCode=$($result.ExitCode)"
        return _New-GenesisResult -Success $false -ExitCode $result.ExitCode -ErrorMessage "rfs-sync --setup failed (ExitCode $($result.ExitCode))." -ErrorDetail $result.StdErr
    }

    Write-GenesisLog -Level INFO -Message "rfs-sync setup completed. RFS: $RfsIp"
    return _New-GenesisResult -Success $true -ExitCode $result.ExitCode
}

function Invoke-RfsSyncUpdate {
    Write-GenesisSection -Title "rfs-sync - Update (Security World Sync)"
    Write-GenesisLog -Level INFO -Message "rfs-sync.exe --update"

    $result = _Invoke-NfastBinary -BinaryName 'rfs-sync.exe' -Arguments @('--update') -TeeToConsole

    if (-not $result.Success) {
        Write-GenesisLog -Level ERROR -Message "rfs-sync --update failed. ExitCode=$($result.ExitCode)"
        return _New-GenesisResult -Success $false -ExitCode $result.ExitCode -ErrorMessage "rfs-sync --update failed (ExitCode $($result.ExitCode))." -ErrorDetail $result.StdErr
    }

    Write-GenesisLog -Level INFO -Message "Security World sync completed."
    return _New-GenesisResult -Success $true -ExitCode $result.ExitCode
}

function Invoke-Enquiry {
    Write-GenesisSection -Title "enquiry - Connection Verification"
    Write-GenesisLog -Level INFO -Message "enquiry.exe"

    $result = _Invoke-NfastBinary -BinaryName 'enquiry.exe' -Arguments @()

    if (-not $result.Success) {
        Write-GenesisLog -Level ERROR -Message "enquiry failed. ExitCode=$($result.ExitCode)"
        return _New-GenesisResult -Success $false -ExitCode $result.ExitCode -ErrorMessage "enquiry failed (ExitCode $($result.ExitCode))." -ErrorDetail $result.StdErr
    }

    $operationalModules = @()
    $blocks = $result.StdOut -split 'Module #'

    if ($blocks.Count -gt 1) {
        for ($i = 1; $i -lt $blocks.Count; $i++) {
            $blk = $blocks[$i]
            $esnMatch = [regex]::Match($blk, 'serial number\s+(.+)')
            $modeMatch = [regex]::Match($blk, 'mode\s+(.+)')
            
            if ($esnMatch.Success -and $modeMatch.Success) {
                if ($modeMatch.Groups[1].Value.Trim().ToLower() -eq 'operational') {
                    $operationalModules += $esnMatch.Groups[1].Value.Trim().ToUpper()
                }
            }
        }
    }

    Write-GenesisLog -Level INFO -Message "enquiry parsed. Operational module count: $($operationalModules.Count)"
    return _New-GenesisResult -Success $true -ExitCode $result.ExitCode -Data @{
        OperationalModules = $operationalModules
        RawOutput          = $result.StdOut
    }
}

function Invoke-NfkmInfo {
    Write-GenesisSection -Title "nfkminfo - Module State Verification"
    Write-GenesisLog -Level INFO -Message "nfkminfo.exe"

    $result = _Invoke-NfastBinary -BinaryName 'nfkminfo.exe' -Arguments @()

    if (-not $result.Success) {
        Write-GenesisLog -Level ERROR -Message "nfkminfo failed. ExitCode=$($result.ExitCode)"
        return _New-GenesisResult -Success $false -ExitCode $result.ExitCode -ErrorMessage "nfkminfo failed (ExitCode $($result.ExitCode))." -ErrorDetail $result.StdErr
    }

    $usableModules = @()
    $blocks = $result.StdOut -split 'Module #'

    if ($blocks.Count -gt 1) {
        for ($i = 1; $i -lt $blocks.Count; $i++) {
            $blk = $blocks[$i]
            $preSlot = ($blk -split 'Slot #')[0]
            
            $esnMatch = [regex]::Match($preSlot, 'ESN\s+(.+)')
            $stateMatch = [regex]::Match($preSlot, 'state\s+(.+)')
            
            if ($esnMatch.Success -and $stateMatch.Success) {
                if ($stateMatch.Groups[1].Value.Trim() -match '0x2 Usable') {
                    $usableModules += $esnMatch.Groups[1].Value.Trim().ToUpper()
                }
            }
        }
    }

    Write-GenesisLog -Level INFO -Message "nfkminfo parsed. Usable module count: $($usableModules.Count)"
    return _New-GenesisResult -Success $true -ExitCode $result.ExitCode -Data @{
        UsableModules = $usableModules
        RawOutput     = $result.StdOut
    }
}

function New-CknfastrcFile {
    $cknfastrcPath = Join-Path $global:GenesisNfastHome 'cknfastrc'

    Write-GenesisSection -Title "cknfastrc - PKCS#11 Configuration"
    Write-GenesisLog -Level INFO -Message "Creating cknfastrc: $cknfastrcPath"

    $content = "CKNFAST_LOADSHARING=1`r`nCKNFAST_OVERRIDE_SECURITY_ASSURANCES=explicitness;tokenkeys;longterm`r`n"

    try {
        [System.IO.File]::WriteAllText($cknfastrcPath, $content, [System.Text.Encoding]::ASCII)
    } catch {
        Write-GenesisLog -Level ERROR -Message "Failed to write cknfastrc: $($_.Exception.Message)"
        return _New-GenesisResult -Success $false -ErrorMessage "Failed to write cknfastrc to $cknfastrcPath." -ErrorDetail $_.Exception.Message
    }

    Write-GenesisLog -Level INFO -Message "cknfastrc written: $cknfastrcPath"
    Write-Host "[OK] cknfastrc created: $cknfastrcPath" -ForegroundColor Green
    return _New-GenesisResult -Success $true -ExitCode 0
}