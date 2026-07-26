#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$global:GenesisStates = @{
    MAIN_MENU     = 'MAIN_MENU'
    VENDOR_SELECT = 'VENDOR_SELECT'
    ENTRUST_ROLE  = 'ENTRUST_ROLE'
    RFS_SETUP     = 'RFS_SETUP'
    CLIENT_SETUP  = 'CLIENT_SETUP'
    CONFIRM_EXIT  = 'CONFIRM_EXIT'
    EXIT          = 'EXIT'
}

function Show-GenesisMainMenu {
    Clear-Host
    Write-Host "  ============================================================"
    Write-Host "    PROJECT GENESIS - INIT v0.2"
    Write-Host "    HSM Day 0 Provisioning Automation"
    Write-Host "  ============================================================"
    Write-Host ""
    Write-Host "    [1] Start Setup"
    Write-Host "    [2] Exit"
    Write-Host ""

    $choice = Read-ValidatedInput -Prompt "    Selection" -Validator { param($v) Test-GenesisChoice -Value $v -ValidOptions @('1', '2') } -ErrorMessage "    [!] Please select 1 or 2."

    if ($choice -eq '1') {
        return $global:GenesisStates.VENDOR_SELECT
    } elseif ($choice -eq '2') {
        return $global:GenesisStates.CONFIRM_EXIT
    }
}

function Show-GenesisVendorMenu {
    Clear-Host
    Write-Host "  ------------------------------------------------------------"
    Write-Host "    Select HSM Vendor"
    Write-Host "  ------------------------------------------------------------"
    Write-Host ""
    Write-Host "    [1] Entrust nShield Connect (network-attached)"
    Write-Host "    [2] Back"
    Write-Host "    [3] Exit"
    Write-Host ""

    $choice = Read-ValidatedInput -Prompt "    Selection" -Validator { param($v) Test-GenesisChoice -Value $v -ValidOptions @('1', '2', '3') } -ErrorMessage "    [!] Please select 1, 2, or 3."

    if ($choice -eq '2') {
        return $global:GenesisStates.MAIN_MENU
    } elseif ($choice -eq '3') {
        return $global:GenesisStates.CONFIRM_EXIT
    } elseif ($choice -eq '1') {
        Write-Host ""
        Write-Host "    +------------------------------------------------------------+"
        Write-Host "    | Entrust nShield Connect - Prerequisites                    |"
        Write-Host "    |                                                            |"
        Write-Host "    | This script supports the following scenario only:          |"
        Write-Host "    |   - HSM has a physical IP configured                       |"
        Write-Host "    |   - Bidirectional TCP/9004 communication is open           |"
        Write-Host "    |     between server and HSM                                 |"
        Write-Host "    |   - nShield Security World client is installed             |"
        Write-Host "    |   - NFAST_HOME environment variable is set                 |"
        Write-Host "    |                                                            |"
        Write-Host "    | Press Enter to continue or 'B' to go back.                 |"
        Write-Host "    +------------------------------------------------------------+"
        Write-Host ""

        $subChoice = Read-ValidatedInput -Prompt "    Action" -Validator { param($v) Test-GenesisChoice -Value $v -ValidOptions @('b', 'B') } -AllowEmpty -ErrorMessage "    [!] Press Enter to continue, or type 'B' to go back."

        if ($subChoice.ToLower() -eq 'b') {
            return $global:GenesisStates.VENDOR_SELECT
        } else {
            return $global:GenesisStates.ENTRUST_ROLE
        }
    }
}

function Show-GenesisEntrustRoleMenu {
    Clear-Host
    Write-Host "  ------------------------------------------------------------"
    Write-Host "    Entrust nShield - Select Server Role"
    Write-Host "  ------------------------------------------------------------"
    Write-Host ""
    Write-Host "    [1] RFS Server Setup"
    Write-Host "    [2] Client Server Setup"
    Write-Host "    [3] Back to vendor selection"
    Write-Host "    [4] Exit"
    Write-Host ""

    $choice = Read-ValidatedInput -Prompt "    Selection" -Validator { param($v) Test-GenesisChoice -Value $v -ValidOptions @('1', '2', '3', '4') } -ErrorMessage "    [!] Please select 1, 2, 3, or 4."

    if ($choice -eq '1') {
        return $global:GenesisStates.RFS_SETUP
    } elseif ($choice -eq '2') {
        return $global:GenesisStates.CLIENT_SETUP
    } elseif ($choice -eq '3') {
        return $global:GenesisStates.VENDOR_SELECT
    } elseif ($choice -eq '4') {
        return $global:GenesisStates.CONFIRM_EXIT
    }
}

function Confirm-GenesisExit {
    Write-Host "  ------------------------------------------------------------"
    Write-Host "    Confirm Exit"
    Write-Host "  ------------------------------------------------------------"
    Write-Host ""

    $choice = Read-ValidatedInput -Prompt "    Are you sure you want to exit? (Y/N)" -Validator { param($v) Test-GenesisYesNo -Value $v } -ErrorMessage "    [!] Please enter Y or N."

    if ($choice -match '^(y|yes)$') {
        return $global:GenesisStates.EXIT
    } else {
        return $global:GenesisStates.MAIN_MENU
    }
}
