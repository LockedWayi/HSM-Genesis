#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$global:GenesisEngineBaseDir = Split-Path -Parent $PSScriptRoot
function _Test-AdminPrivilege {
    $identity  = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [System.Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}

function _Test-NfastBinaries {
    $binaries = @(
        'anonkneti.exe', 'rfs-setup.exe', 'cfg-pushnethsm.exe',
        'nethsmenroll.exe', 'rfs-sync.exe', 'enquiry.exe', 'nfkminfo.exe'
    )
    $missing = @()
    foreach ($bin in $binaries) {
        $path = Join-Path $global:GenesisNfastBinPath $bin
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            $missing += $bin
        }
    }
    return $missing
}

function Invoke-RfsWorkflow {
    while ($true) {
        Write-Host "  ============================================================"
        Write-Host "    RFS Server Setup"
        Write-Host "  ============================================================"
        Write-Host ""

        $cont = Read-ValidatedInput -Prompt "    Continue? (Y/N)" -Validator { param($v) Test-GenesisYesNo -Value $v }
        if ($cont -match '^(n|no)$') { return $global:GenesisStates.ENTRUST_ROLE }

        $hsmIp = ""
        $cachedEsn = ""
        $cachedKeyhash = ""

        while ($true) {
            if (-not $hsmIp) {

                $hsmIp = Read-ValidatedInput -Prompt "  HSM IP address" -Validator { param($v) Test-GenesisIPv4 -Value $v } -ErrorMessage "  [!] Enter a valid IPv4 address."
            }

            Write-Host "  Testing HSM connectivity via anonkneti..." -ForegroundColor Cyan
            $anonResult = Invoke-Anonkneti -HsmIp $hsmIp

            if ($anonResult.Success) {
                $cachedEsn = $anonResult.Data.ESN
                $cachedKeyhash = $anonResult.Data.Keyhash
                break
            } else {
                Write-GenesisLog -Level ERROR -Message $anonResult.ErrorMessage
                Write-Host ""
                Write-Host "  [FAILED] $($anonResult.ErrorMessage)" -ForegroundColor Red
                if ($anonResult.ErrorDetail) {
                    Write-Host "  Detail : $($anonResult.ErrorDetail)" -ForegroundColor DarkRed
                }
                Write-Host ""
                $retry = Read-ValidatedInput -Prompt "  Retry with the same IP? (Y/N)" -Validator { param($v) Test-GenesisYesNo -Value $v }
                if ($retry -match '^(n|no)$') {
                    $hsmIp = ""
                }
            }
        }

        $clientCount = [int](Read-ValidatedInput -Prompt "  Client count (0-20)" -Validator { param($v) Test-GenesisInteger -Value $v -Min 0 -Max 20 })

        if ($clientCount -eq 0) {
            Write-GenesisLog -Level WARN -Message "No client will be whitelisted. RFS enrollment will proceed without clients."
            $c0 = Read-ValidatedInput -Prompt "  Continue with 0 clients? (Y/N)" -Validator { param($v) Test-GenesisYesNo -Value $v }
            if ($c0 -match '^(n|no)$') { continue }
        }

        $clientIps = @()
        for ($i = 1; $i -le $clientCount; $i++) {
            while ($true) {

                $cip = Read-ValidatedInput -Prompt "  Client $i IP" -Validator { param($v) Test-GenesisIPv4 -Value $v } -ErrorMessage "  [!] Invalid IPv4."
                if ($clientIps.Count -gt 0 -and (Test-GenesisDuplicate -Value $cip -ExistingList $clientIps)) {
                    Write-Host "  [!] Duplicate IP entered." -ForegroundColor Yellow
                    continue
                }
                $clientIps += $cip
                break
            }
        }

        $clientPerm = 'priv'
        if ($clientCount -gt 0) {
            Write-Host "  Select client permission mode:"
            Write-Host "  [1] priv        (recommended for RFS acting as client too)"
            Write-Host "  [2] unpriv      (recommended for production apps)"
            Write-Host "  [3] priv_lowport"

            $permChoice = Read-ValidatedInput -Prompt "  Selection [1]" -Validator { param($v) Test-GenesisChoice -Value $v -ValidOptions @('1','2','3') } -Default '1'
            $clientPerm = switch ($permChoice) { '1'{'priv'}; '2'{'unpriv'}; '3'{'priv_lowport'} }
        }

        $usesNtoken = $false
        if ($clientCount -gt 0) {
            $nt = Read-ValidatedInput -Prompt "  Do any clients use an nToken? (Y/N) [N]" -Validator { param($v) Test-GenesisYesNo -Value $v } -Default 'N'
            if ($nt -match '^(y|yes)$') {
                $usesNtoken = $true
                Write-Host "  [WARN] nToken support is not automated. Manual configuration required later." -ForegroundColor Yellow
                $contN = Read-ValidatedInput -Prompt "  Understood, continue? (Y/N)" -Validator { param($v) Test-GenesisYesNo -Value $v }
                if ($contN -match '^(n|no)$') { return $global:GenesisStates.ENTRUST_ROLE }
            }
        }

        Write-Host "  ------------------------------------------------------------"
        Write-Host "    Review Setup Parameters"
        Write-Host "  ------------------------------------------------------------"
        Write-Host "  HSM IP        : $hsmIp"
        Write-Host "  HSM ESN       : $cachedEsn"
        Write-Host "  HSM Keyhash   : $cachedKeyhash"
        Write-Host "  Client Count  : $clientCount"
        if ($clientCount -gt 0) {
            Write-Host "  Client IPs    : $($clientIps -join ', ')"
            Write-Host "  Client Perm   : $clientPerm"
            Write-Host "  Uses nToken   : $(if($usesNtoken){'Yes'}else{'No'})"
        }
        Write-Host ""

        $proc = Read-ValidatedInput -Prompt "  Proceed with setup? (Y/N)" -Validator { param($v) Test-GenesisYesNo -Value $v }
        if ($proc -match '^(y|yes)$') { break }
    }

    Start-GenesisStep -Name "RFS enrollment"
    while ($true) {
        $enrollResult = Invoke-RfsSetupEnroll -HsmIp $hsmIp -Esn $cachedEsn -Keyhash $cachedKeyhash
        if ($enrollResult.Success) {
            Complete-GenesisStep -Status 'Success'
            break
        } else {
            Write-GenesisLog -Level ERROR -Message $enrollResult.ErrorMessage

            Write-Host ""
            Write-Host "  [FAILED] $($enrollResult.ErrorMessage)" -ForegroundColor Red
            if ($enrollResult.ErrorDetail) {
                Write-Host "  Detail : $($enrollResult.ErrorDetail)" -ForegroundColor DarkRed
            }
            Write-Host ""

            $rba = Read-ValidatedInput -Prompt "  Retry, Back to inputs, or Abort? (R/B/A)" -Validator { param($v) Test-GenesisChoice -Value $v -ValidOptions @('r','b','a') }
            if ($rba -match 'a') { Complete-GenesisStep -Status 'Failed' -ErrorMessage "Aborted"; return $global:GenesisStates.ENTRUST_ROLE }
            if ($rba -match 'b') { Complete-GenesisStep -Status 'Failed' -ErrorMessage "Back"; return $global:GenesisStates.RFS_SETUP }
        }
    }

    if ($clientCount -gt 0) {
        Start-GenesisStep -Name "Client whitelist"
        foreach ($cip in $clientIps) {
            while ($true) {
                $gangResult = Invoke-RfsSetupGangClient -ClientIp $cip
                if ($gangResult.Success) {
                    break
                } else {
                    Write-GenesisLog -Level ERROR -Message $gangResult.ErrorMessage

                    Write-Host ""
                    Write-Host "  [FAILED] $($gangResult.ErrorMessage)" -ForegroundColor Red
                    if ($gangResult.ErrorDetail) {
                        Write-Host "  Detail : $($gangResult.ErrorDetail)" -ForegroundColor DarkRed
                    }
                    Write-Host ""

                    $rsa = Read-ValidatedInput -Prompt "  Retry, Skip this client, or Abort? (R/S/A)" -Validator { param($v) Test-GenesisChoice -Value $v -ValidOptions @('r','s','a') }
                    if ($rsa -match 'a') { Complete-GenesisStep -Status 'Failed' -ErrorMessage "Aborted"; return $global:GenesisStates.ENTRUST_ROLE }
                    if ($rsa -match 's') { Write-GenesisLog -Level WARN -Message "Skipped whitelist for $cip"; break }
                }
            }
        }
        Complete-GenesisStep -Status 'Success'

        Start-GenesisStep -Name "hs_clients config edit"
        $hsmConfigPath = Join-Path $global:GenesisNfastKmDataPath "hsm-$cachedEsn\config"
        $configFound = $false
        while ($true) {
            if (-not (Test-Path -LiteralPath $hsmConfigPath -PathType Leaf)) {
                Write-GenesisLog -Level ERROR -Message "Expected HSM config not found: $hsmConfigPath"

                $ra = Read-ValidatedInput -Prompt "  Retry file check, or Abort? (R/A)" -Validator { param($v) Test-GenesisChoice -Value $v -ValidOptions @('r','a') }
                if ($ra -match 'a') { Complete-GenesisStep -Status 'Failed' -ErrorMessage "Aborted"; return $global:GenesisStates.ENTRUST_ROLE }
                continue
            }
            $configFound = $true
            break
        }

        if ($configFound) {
            foreach ($cip in $clientIps) {
                $editResult = Add-HsClientEntry -FilePath $hsmConfigPath -ClientIp $cip -ClientPerm $clientPerm
                if (-not $editResult.Success) {
                    Write-GenesisLog -Level ERROR -Message $editResult.ErrorMessage
                    $ab = Read-ValidatedInput -Prompt "  Abort and go back? (Y/N) [Y]" -Validator { param($v) Test-GenesisYesNo -Value $v } -Default 'Y'
                    if ($ab -match '^(y|yes)$') { Complete-GenesisStep -Status 'Failed' -ErrorMessage "Aborted"; return $global:GenesisStates.ENTRUST_ROLE }
                }
            }
            Complete-GenesisStep -Status 'Success'
        }

        Start-GenesisStep -Name "Config push to HSM"
        $pushWorkDir = Join-Path $global:GenesisEngineBaseDir "output\push-workdir"
        while ($true) {
            Invoke-PushWorkdirCleanup -PushWorkDir $pushWorkDir
            Copy-Item -LiteralPath $hsmConfigPath -Destination (Join-Path $pushWorkDir 'config') -Force

            $pushResult = Invoke-CfgPushNethsm -HsmIp $hsmIp -ConfigPath (Join-Path $pushWorkDir 'config')
            if ($pushResult.Success) {
                Complete-GenesisStep -Status 'Success'
                break
            } else {
                Write-GenesisLog -Level ERROR -Message $pushResult.ErrorMessage

                Write-Host ""
                Write-Host "  [FAILED] $($pushResult.ErrorMessage)" -ForegroundColor Red
                if ($pushResult.ErrorDetail) {
                    Write-Host "  Detail : $($pushResult.ErrorDetail)" -ForegroundColor DarkRed
                }
                Write-Host ""

                $ra = Read-ValidatedInput -Prompt "  Retry push, or Abort? (R/A)" -Validator { param($v) Test-GenesisChoice -Value $v -ValidOptions @('r','a') }
                if ($ra -match 'a') { Complete-GenesisStep -Status 'Failed' -ErrorMessage "Aborted"; return $global:GenesisStates.ENTRUST_ROLE }
            }
        }
    }

    Write-Host "  ============================================================"
    Write-Host "    RFS Server Setup COMPLETED"
    Write-Host "  ============================================================"
    Write-Host "  HSM       : $hsmIp ($cachedEsn)"
    Write-Host "  Clients   : $clientCount whitelisted"

    Write-Host "  [1] Setup another HSM"
    Write-Host "  [2] Return to main menu"
    Write-Host "  [3] Exit"
    $fin = Read-ValidatedInput -Prompt "  Selection" -Validator { param($v) Test-GenesisChoice -Value $v -ValidOptions @('1','2','3') }
    if ($fin -eq '1') { return $global:GenesisStates.ENTRUST_ROLE }
    if ($fin -eq '2') { return $global:GenesisStates.MAIN_MENU }
    if ($fin -eq '3') { return $global:GenesisStates.CONFIRM_EXIT }
}

function Invoke-ClientWorkflow {

    while ($true) {
        Write-Host "  ============================================================"
        Write-Host "    Client Server Setup"
        Write-Host "  ============================================================"
        Write-Host ""

        $cont = Read-ValidatedInput -Prompt "    Continue? (Y/N)" -Validator { param($v) Test-GenesisYesNo -Value $v }
        if ($cont -match '^(n|no)$') { return $global:GenesisStates.ENTRUST_ROLE }

        $rfsIp = ""
        while ($true) {
            if (-not $rfsIp) {

                $rfsIp = Read-ValidatedInput -Prompt "  RFS Server IP address" -Validator { param($v) Test-GenesisIPv4 -Value $v }
            }

            Write-Host "  Testing RFS connectivity via ping..." -ForegroundColor Cyan
            $pingCount = 0
            try {
                $pings = Test-Connection -ComputerName $rfsIp -Count 3 -ErrorAction SilentlyContinue
                if ($pings) { 
                    if ($pings -is [array]) { $pingCount = $pings.Count }
                    else { $pingCount = 1 }
                }
            } catch {}

            if ($pingCount -eq 0) {
                Write-GenesisLog -Level ERROR -Message "RFS is unreachable at $rfsIp."

                $rca = Read-ValidatedInput -Prompt "  Retry, Change IP, or Abort? (R/C/A)" -Validator { param($v) Test-GenesisChoice -Value $v -ValidOptions @('r','c','a') }
                if ($rca -match 'a') { return $global:GenesisStates.ENTRUST_ROLE }
                if ($rca -match 'c') { $rfsIp = ""; continue }
                if ($rca -match 'r') { continue }
            } elseif ($pingCount -lt 3) {
                Write-GenesisLog -Level WARN -Message "Partial ping success ($pingCount/3). RFS may have intermittent connectivity."
                $contP = Read-ValidatedInput -Prompt "  Continue anyway? (Y/N)" -Validator { param($v) Test-GenesisYesNo -Value $v }
                if ($contP -match '^(n|no)$') { $rfsIp = ""; continue }
                break
            } else {
                break
            }
        }

        $hsmCount = [int](Read-ValidatedInput -Prompt "  How many HSMs to enroll on this client? (1-10)" -Validator { param($v) Test-GenesisInteger -Value $v -Min 0 -Max 20 })

        $hsmIps = @()
        $hsmIdentities = @{}
        $hsmEntries = @()

        $i = 1
        while ($i -le $hsmCount) {
            $hip = ""
            while ($true) {
                if (-not $hip) {

                    $hip = Read-ValidatedInput -Prompt "  HSM $i IP" -Validator { param($v) Test-GenesisIPv4 -Value $v }
                    if ($hsmIps.Count -gt 0 -and (Test-GenesisDuplicate -Value $hip -ExistingList $hsmIps)) {
                        Write-Host "  [!] Duplicate IP entered" -ForegroundColor Yellow
                        $hip = ""
                        continue
                    }
                }

                Write-Host "  Testing HSM $i connectivity via anonkneti..." -ForegroundColor Cyan
                $anonResult = Invoke-Anonkneti -HsmIp $hip
                if ($anonResult.Success) {
                    $hsmIps += $hip
                    $hsmIdentities[$hip] = $anonResult.Data
                    $hsmEntries += [PSCustomObject]@{
                        IP      = $hip
                        ESN     = $anonResult.Data.ESN
                        Keyhash = $anonResult.Data.Keyhash
                    }
                    $i++
                    break
                } else {
                    Write-GenesisLog -Level ERROR -Message $anonResult.ErrorMessage

                    Write-Host ""
                    Write-Host "  [FAILED] $($anonResult.ErrorMessage)" -ForegroundColor Red
                    if ($anonResult.ErrorDetail) {
                        Write-Host "  Detail : $($anonResult.ErrorDetail)" -ForegroundColor DarkRed
                    }
                    Write-Host ""

                    $rcsa = Read-ValidatedInput -Prompt "  Retry, Change IP, Skip this HSM, Abort? (R/C/S/A)" -Validator { param($v) Test-GenesisChoice -Value $v -ValidOptions @('r','c','s','a') }
                    if ($rcsa -match 'a') { return $global:GenesisStates.ENTRUST_ROLE }
                    if ($rcsa -match 's') { $hsmCount--; break }
                    if ($rcsa -match 'c') { $hip = ""; continue }
                    if ($rcsa -match 'r') { continue }
                }
            }
        }

        if ($hsmCount -eq 0) {
            Write-GenesisLog -Level WARN -Message "All HSMs skipped. Aborting."
            return $global:GenesisStates.ENTRUST_ROLE
        }

        $clientCount = [int](Read-ValidatedInput -Prompt "  How many client IPs to register in [hs_clients]? (1-10)" -Validator { param($v) Test-GenesisInteger -Value $v -Min 1 -Max 10 })

        $clientIps = @()
        $clientEntries = @()
        for ($k = 1; $k -le $clientCount; $k++) {
            while ($true) {
                $cip = Read-ValidatedInput -Prompt "  Client $k IP" -Validator { param($v) Test-GenesisIPv4 -Value $v }
                if ($clientIps.Count -gt 0 -and (Test-GenesisDuplicate -Value $cip -ExistingList $clientIps)) {
                    Write-Host "  [!] Duplicate IP entered" -ForegroundColor Yellow
                    continue
                }
                $clientIps += $cip

                Write-Host "  Permission level for $cip?"
                Write-Host "  [1] priv"
                Write-Host "  [2] unpriv"
                Write-Host "  [3] priv_lowport"
                $permChoice = Read-ValidatedInput -Prompt "  Selection [1]" -Validator { param($v) Test-GenesisChoice -Value $v -ValidOptions @('1','2','3') } -Default '1'
                $cPerm = switch ($permChoice) { '1'{'priv'}; '2'{'unpriv'}; '3'{'priv_lowport'} }

                $clientEntries += [PSCustomObject]@{
                    IP   = $cip
                    Perm = $cPerm
                }
                break
            }
        }

        Write-Host "  ------------------------------------------------------------"
        Write-Host "    Review Setup Parameters"
        Write-Host "  ------------------------------------------------------------"
        Write-Host "  RFS IP        : $rfsIp"
        Write-Host "  HSM Count     : $hsmCount"
        foreach ($hip in $hsmIps) {
            Write-Host "    - $hip ($($hsmIdentities[$hip].ESN))"
        }
        Write-Host "  Client Count  : $clientCount"
        foreach ($c in $clientEntries) {
            Write-Host "    - $($c.IP) ($($c.Perm))"
        }
        Write-Host ""

        $proc = Read-ValidatedInput -Prompt "  Proceed with setup? (Y/N)" -Validator { param($v) Test-GenesisYesNo -Value $v }
        if ($proc -match '^(y|yes)$') { break }
    }

    Start-GenesisStep -Name "Generate hardserver.cfg"
    $templatePath = Join-Path $global:GenesisEngineBaseDir 'vendors\entrust\templates\hardserver.cfg.template'
    while ($true) {
        if (-not (Test-Path -LiteralPath $templatePath -PathType Leaf)) {
            Write-GenesisLog -Level ERROR -Message "Template file missing: $templatePath"

            $ra = Read-ValidatedInput -Prompt "  Retry check, or Abort? (R/A)" -Validator { param($v) Test-GenesisChoice -Value $v -ValidOptions @('r','a') }
            if ($ra -match 'a') { Complete-GenesisStep -Status 'Failed'; return $global:GenesisStates.ENTRUST_ROLE }
            continue
        }
        break
    }

    $outputPath = Join-Path $global:GenesisNfastKmDataPath 'config\config'
    if (-not (Test-Path -LiteralPath $outputPath -PathType Leaf)) {
        Write-GenesisLog -Level WARN -Message "No existing hardserver.cfg found. Version mismatch warning."
        $cont = Read-ValidatedInput -Prompt "  Continue? (Y/N)" -Validator { param($v) Test-GenesisYesNo -Value $v }
        if ($cont -match '^(n|no)$') { Complete-GenesisStep -Status 'Failed'; return $global:GenesisStates.ENTRUST_ROLE }
    }

    $backupDir = Join-Path $global:GenesisEngineBaseDir 'output\backups'
    $genResult = New-EntrustHardserverConfig -HsmEntries $hsmEntries -TemplatePath $templatePath -OutputPath $outputPath -BackupDir $backupDir
    if (-not $genResult.Success) {
        Write-GenesisLog -Level ERROR -Message $genResult.ErrorMessage
        Complete-GenesisStep -Status 'Failed'
        return $global:GenesisStates.ENTRUST_ROLE
    }
    Complete-GenesisStep -Status 'Success'

    Start-GenesisStep -Name "Add client entries"
    foreach ($client in $clientEntries) {
        while ($true) {
            $addResult = Add-HsClientEntry -FilePath $outputPath -ClientIp $client.IP -ClientPerm $client.Perm
            
            if ($addResult.Success) {
                break
            } else {
                Write-GenesisLog -Level ERROR -Message $addResult.ErrorMessage
                
                Write-Host ""
                Write-Host "  [FAILED] $($addResult.ErrorMessage)" -ForegroundColor Red
                if ($addResult.ErrorDetail) {
                    Write-Host "  Detail : $($addResult.ErrorDetail)" -ForegroundColor DarkRed
                }
                Write-Host ""
                
                $rsa = Read-ValidatedInput -Prompt "  Retry, Skip this client, or Abort? (R/S/A)" -Validator { param($v) Test-GenesisChoice -Value $v -ValidOptions @('r','s','a') }
                if ($rsa -match 'a') { Complete-GenesisStep -Status 'Failed'; return $global:GenesisStates.ENTRUST_ROLE }
                if ($rsa -match 's') { break }
            }
        }
    }
    Complete-GenesisStep -Status 'Success'

    Start-GenesisStep -Name "nethsmenroll for all HSMs"
    for ($idx = 0; $idx -lt $hsmIps.Count; $idx++) {
        $hip = $hsmIps[$idx]
        while ($true) {
            $enrollResult = Invoke-NethsmEnroll -HsmIp $hip
            if ($enrollResult.Success) { break }
            else {
                Write-GenesisLog -Level ERROR -Message $enrollResult.ErrorMessage

                Write-Host ""
                Write-Host "  [FAILED] $($enrollResult.ErrorMessage)" -ForegroundColor Red
                if ($enrollResult.ErrorDetail) {
                    Write-Host "  Detail : $($enrollResult.ErrorDetail)" -ForegroundColor DarkRed
                }
                Write-Host ""

                $rcsa = Read-ValidatedInput -Prompt "  Retry, Change IP, Skip, or Abort? (R/C/S/A)" -Validator { param($v) Test-GenesisChoice -Value $v -ValidOptions @('r','c','s','a') }
                if ($rcsa -match 'a') { Complete-GenesisStep -Status 'Failed'; return $global:GenesisStates.ENTRUST_ROLE }
                if ($rcsa -match 's') { break }
                if ($rcsa -match 'c') { 

                    $newIp = Read-ValidatedInput -Prompt "  New HSM IP" -Validator { param($v) Test-GenesisIPv4 -Value $v }
                    $anon = Invoke-Anonkneti -HsmIp $newIp
                    if ($anon.Success) {
                        $hip = $newIp
                        $hsmIps[$idx] = $newIp
                        $hsmIdentities[$newIp] = $anon.Data
                    }
                    continue
                }
                if ($rcsa -match 'r') { continue }
            }
        }
    }
    Complete-GenesisStep -Status 'Success'

    Start-GenesisStep -Name "rfs-sync setup"
    while ($true) {
        $syncSetup = Invoke-RfsSyncSetup -RfsIp $rfsIp
        if ($syncSetup.Success) { break }

        Write-GenesisLog -Level ERROR -Message $syncSetup.ErrorMessage

        Write-Host ""
        Write-Host "  [FAILED] $($syncSetup.ErrorMessage)" -ForegroundColor Red
        if ($syncSetup.ErrorDetail) {
            Write-Host "  Detail : $($syncSetup.ErrorDetail)" -ForegroundColor DarkRed
        }
        Write-Host ""

        $ra = Read-ValidatedInput -Prompt "  Retry, or Abort? (R/A)" -Validator { param($v) Test-GenesisChoice -Value $v -ValidOptions @('r','a') }
        if ($ra -match 'a') { Complete-GenesisStep -Status 'Failed'; return $global:GenesisStates.ENTRUST_ROLE }
    }
    Complete-GenesisStep -Status 'Success'

    Start-GenesisStep -Name "rfs-sync update"
    while ($true) {
        $syncUpdate = Invoke-RfsSyncUpdate
        if ($syncUpdate.Success) { break }

        Write-GenesisLog -Level ERROR -Message $syncUpdate.ErrorMessage

        Write-Host ""
        Write-Host "  [FAILED] $($syncUpdate.ErrorMessage)" -ForegroundColor Red
        if ($syncUpdate.ErrorDetail) {
            Write-Host "  Detail : $($syncUpdate.ErrorDetail)" -ForegroundColor DarkRed
        }
        Write-Host ""

        $ra = Read-ValidatedInput -Prompt "  Retry, or Abort? (R/A)" -Validator { param($v) Test-GenesisChoice -Value $v -ValidOptions @('r','a') }
        if ($ra -match 'a') { Complete-GenesisStep -Status 'Failed'; return $global:GenesisStates.ENTRUST_ROLE }
    }
    Complete-GenesisStep -Status 'Success'

    Start-GenesisStep -Name "enquiry verification"
    $enqResult = Invoke-Enquiry
    if (-not $enqResult.Success) {
        Write-GenesisLog -Level ERROR -Message $enqResult.ErrorMessage
        Write-Host ""
        Write-Host "  [FAILED] $($enqResult.ErrorMessage)" -ForegroundColor Red
        if ($enqResult.ErrorDetail) {
            Write-Host "  Detail : $($enqResult.ErrorDetail)" -ForegroundColor DarkRed
        }
        Write-Host ""
        Complete-GenesisStep -Status 'Failed'
    } else {
        $blocks = $enqResult.Data.RawOutput -split 'Module #'
        $operationalEsns = @()
        if ($blocks.Count -gt 1) {
            for ($k = 1; $k -lt $blocks.Count; $k++) {
                $blk = $blocks[$k]
                $esnMatch = [regex]::Match($blk, 'serial number\s+([0-9A-Fa-f\-]{14})')
                $modeMatch = [regex]::Match($blk, 'mode\s+operational')
                if ($esnMatch.Success -and $modeMatch.Success) {
                    $operationalEsns += $esnMatch.Groups[1].Value.ToUpper()
                }
            }
        }

        $allOperational = $true
        $missingEsns = @()
        foreach ($hip in $hsmIps) {
            $expectedEsn = $hsmIdentities[$hip].ESN
            if ($operationalEsns -notcontains $expectedEsn) {
                $allOperational = $false
                $missingEsns += $expectedEsn
            }
        }

        if ($allOperational) {
            Write-GenesisLog -Level INFO -Message "All expected HSMs operational"
            Complete-GenesisStep -Status 'Success'
        } else {
            Write-GenesisLog -Level WARN -Message "The following HSMs are NOT operational in enquiry:`r`n  - $($missingEsns -join "`r`n  - ")"
            Complete-GenesisStep -Status 'Warning'
        }
    }

    Start-GenesisStep -Name "nfkminfo cross-check"
    $nfResult = Invoke-NfkmInfo
    if (-not $nfResult.Success) {
        Write-GenesisLog -Level ERROR -Message $nfResult.ErrorMessage
        Write-Host ""
        Write-Host "  [FAILED] $($nfResult.ErrorMessage)" -ForegroundColor Red
        if ($nfResult.ErrorDetail) {
            Write-Host "  Detail : $($nfResult.ErrorDetail)" -ForegroundColor DarkRed
        }
        Write-Host ""
        Complete-GenesisStep -Status 'Failed'
    } else {
        $nfBlocks = $nfResult.Data.RawOutput -split 'Module #'
        $usableEsns = @()
        if ($nfBlocks.Count -gt 1) {
            for ($k = 1; $k -lt $nfBlocks.Count; $k++) {
                $blk = $nfBlocks[$k]
                $modPart = ($blk -split 'Slot #')[0]
                $esnMatch = [regex]::Match($modPart, 'esn\s+([0-9A-Fa-f\-]{14})')
                $stateMatch = [regex]::Match($modPart, 'state 0x2 Usable')
                if ($esnMatch.Success -and $stateMatch.Success) {
                    $usableEsns += $esnMatch.Groups[1].Value.ToUpper()
                }
            }
        }

        $nfAllUsable = $true
        foreach ($hip in $hsmIps) {
            $expectedEsn = $hsmIdentities[$hip].ESN
            if ($usableEsns -notcontains $expectedEsn) {
                $nfAllUsable = $false
                Write-GenesisLog -Level WARN -Message "HSM $expectedEsn state in nfkminfo is not Usable."
            }
        }

        if ($nfAllUsable) {
            Write-GenesisLog -Level INFO -Message "nfkminfo confirms all HSMs Usable"
            Complete-GenesisStep -Status 'Success'
        } else {
            $cont = Read-ValidatedInput -Prompt "  Continue to cknfastrc step? (Y/N)" -Validator { param($v) Test-GenesisYesNo -Value $v }
            if ($cont -match '^(n|no)$') {
                Complete-GenesisStep -Status 'Failed'
                return $global:GenesisStates.ENTRUST_ROLE
            }
            Complete-GenesisStep -Status 'Warning'
        }
    }

    Start-GenesisStep -Name "Create cknfastrc"
    $cknResult = New-CknfastrcFile
    if (-not $cknResult.Success) {
        Write-GenesisLog -Level ERROR -Message $cknResult.ErrorMessage
        Complete-GenesisStep -Status 'Failed'
    } else {
        Complete-GenesisStep -Status 'Success'
    }

    Write-Host "  ============================================================"
    Write-Host "    Client Server Setup COMPLETED"
    Write-Host "  ============================================================"

    Write-Host "  [1] Setup another Server"
    Write-Host "  [2] Return to main menu"
    Write-Host "  [3] Exit"
    $fin = Read-ValidatedInput -Prompt "  Selection" -Validator { param($v) Test-GenesisChoice -Value $v -ValidOptions @('1','2','3') }
    if ($fin -eq '1') { return $global:GenesisStates.ENTRUST_ROLE }
    if ($fin -eq '2') { return $global:GenesisStates.MAIN_MENU }
    if ($fin -eq '3') { return $global:GenesisStates.CONFIRM_EXIT }
}

function Start-GenesisEngine {

    $logDir = Join-Path $global:GenesisEngineBaseDir 'output\logs'
    if (-not (Test-Path -LiteralPath $logDir)) {
        $null = New-Item -Path $logDir -ItemType Directory -Force
    }

    $dateSuffix = Get-Date -Format 'yyyyMMdd'
    $global:GenesisLogFile = Join-Path $logDir "genesis_$dateSuffix.log"
    $global:GenesisLogInitialized = $true

    $sessionHeader = @('', ('=' * 72), "  Genesis-Init Session Started : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')", "  User                         : $($env:USERNAME)", "  Hostname                     : $($env:COMPUTERNAME)", ('=' * 72), '')
    foreach ($line in $sessionHeader) {
        Add-Content -LiteralPath $global:GenesisLogFile -Value $line -Encoding ASCII
    }

    if (-not (_Test-AdminPrivilege)) {
        Write-GenesisLog -Level ERROR -Message "Admin privilege check failed."
        Write-Host ""
        Write-Host "[ERROR] This script must be run with Administrator privileges." -ForegroundColor Red
        Write-Host ""
        exit 1
    }

    Initialize-Workflow
    Invoke-BackupRetention -BackupDir (Join-Path $global:GenesisEngineBaseDir 'output\backups')

    $vendorModules = @(
        'vendors\entrust\HardserverConfig.ps1',
        'vendors\entrust\BinaryRunner.ps1'
    )
    foreach ($mod in $vendorModules) {
        $path = Join-Path $global:GenesisEngineBaseDir $mod
        try {
            . $path
        } catch {
            Write-GenesisLog -Level ERROR -Message "Module failed to load: $path"
            exit 1
        }
    }

    if (-not $env:NFAST_HOME) {
        Write-GenesisLog -Level WARN -Message "NFAST_HOME environment variable is missing."
        Write-Host "[WARN] NFAST_HOME is not set in environment." -ForegroundColor Yellow

        $cont = Read-ValidatedInput -Prompt "Continue with default (C:\Program Files\nCipher\nfast)? (Y/N)" -Validator { param($v) Test-GenesisYesNo -Value $v } -Default 'Y'
        if ($cont -match '^(n|no)$') { exit 1 }
    }

    $missingBins = @(_Test-NfastBinaries)
    if ($missingBins.Count -gt 0) {
        Write-GenesisLog -Level WARN -Message "Missing binaries: $($missingBins -join ', ')"
        Write-Host "[WARN] The following nShield binaries were not found:" -ForegroundColor Yellow
        foreach ($b in $missingBins) { Write-Host "  - $b" -ForegroundColor Yellow }

        $cont = Read-ValidatedInput -Prompt "Continue anyway? (Y/N)" -Validator { param($v) Test-GenesisYesNo -Value $v } -Default 'N'
        if ($cont -match '^(n|no)$') { exit 1 }
    }

    $state = $global:GenesisStates.MAIN_MENU
    while ($state -ne $global:GenesisStates.EXIT) {
        $state = switch ($state) {
            $global:GenesisStates.MAIN_MENU     { Show-GenesisMainMenu }
            $global:GenesisStates.VENDOR_SELECT { Show-GenesisVendorMenu }
            $global:GenesisStates.ENTRUST_ROLE  { Show-GenesisEntrustRoleMenu }
            $global:GenesisStates.RFS_SETUP     { Invoke-RfsWorkflow }
            $global:GenesisStates.CLIENT_SETUP  { Invoke-ClientWorkflow }
            $global:GenesisStates.CONFIRM_EXIT  { Confirm-GenesisExit }
            default {
                Write-GenesisLog -Level ERROR -Message "Unknown state: $state"
                $global:GenesisStates.MAIN_MENU
            }
        }
    }

    Show-GenesisSummary
    Write-GenesisLog -Level INFO -Message "Session ended."
}
