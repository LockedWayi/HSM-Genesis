#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Test-GenesisIPv4 {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $false
    }

    $Value = $Value.Trim()

    # Matches four dot-separated octets, each 0-255.
    # Rejects leading zeros (e.g., 01, 001) but allows a single '0'.
    $octetRegex = '(25[0-5]|2[0-4]\d|1\d\d|[1-9]\d|\d)'
    $ipRegex = "^$octetRegex\.$octetRegex\.$octetRegex\.$octetRegex`$"

    return ($Value -match $ipRegex)
}

function Test-GenesisInteger {
    param(
        [string]$Value,
        [int]$Min,
        [int]$Max
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $false
    }

    $Value = $Value.Trim()

    # Must be a base-10 integer, allowing optional negative sign.
    if ($Value -notmatch '^-?\d+$') {
        return $false
    }

    $parsed = 0
    if ([int]::TryParse($Value, [ref]$parsed)) {
        if ($parsed -ge $Min -and $parsed -le $Max) {
            return $true
        }
    }

    return $false
}

function Test-GenesisChoice {
    param(
        [string]$Value,
        [string[]]$ValidOptions
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $false
    }

    $Value = $Value.Trim()

    foreach ($option in $ValidOptions) {
        if ($option -eq $Value) {
            return $true
        }
    }

    return $false
}

function Test-GenesisYesNo {
    param([Parameter(Mandatory)][string] $Value)
    return ($Value.Trim() -imatch '^(y|yes|n|no)$')
}

function Test-GenesisNonEmpty {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $false
    }

    return $true
}

function Read-ValidatedInput {
    <#
    .SYNOPSIS
        Prompts the user and re-prompts on invalid input. Never throws,
        never returns invalid data. This is the ONLY way user input should
        be collected anywhere in this project going forward.

    .PARAMETER Prompt
        Text shown to the user via Read-Host.

    .PARAMETER Validator
        A scriptblock that takes one string argument and returns $true/$false.
        Example: { param($v) Test-GenesisIPv4 -Value $v }

    .PARAMETER ErrorMessage
        Shown (via Write-Host, yellow) when validation fails, before re-prompting.

    .PARAMETER Default
        Optional. If the user presses Enter with no input, this value is
        returned WITHOUT being passed through the validator. If not supplied
        and the user presses Enter, treat it as empty input and let the
        validator decide (most validators will reject empty input via
        Test-GenesisNonEmpty composition — see notes below).

    .PARAMETER AllowEmpty
        Switch. If set, empty input bypasses the validator and returns
        an empty string. Default: $false.

    .OUTPUTS
        [string] — the raw validated input, or the Default value.
    #>
    param(
        [Parameter(Mandatory)] [string] $Prompt,
        [Parameter(Mandatory)] [scriptblock] $Validator,
        [string] $ErrorMessage = "Invalid input. Please try again.",
        [string] $Default = $null,
        [switch] $AllowEmpty
    )

    while ($true) {
        $rawInput = Read-Host $Prompt

        if ($rawInput -eq '') {
            if ($PSBoundParameters.ContainsKey('Default')) {
                return $Default
            }
            if ($AllowEmpty) {
                return ''
            }
        }

        $isValid = & $Validator $rawInput

        if ($isValid) {
            return $rawInput
        }

        Write-GenesisLog -Level DEBUG -Message "Validation failed for input: '$rawInput'" -NoConsole
        Write-Host $ErrorMessage -ForegroundColor Yellow
    }
}

function Test-GenesisDuplicate {
    <#
    .SYNOPSIS
        Checks if $Value already exists in $ExistingList (case-insensitive
        string comparison). Used when collecting multiple IPs in a loop
        (client IPs, HSM IPs) to warn on duplicate entry.
    #>
    param(
        [Parameter(Mandatory)] [string]   $Value,
        [Parameter(Mandatory)] [string[]] $ExistingList
    )

    $Value = $Value.Trim()

    if (-not $ExistingList) {
        return $false
    }

    foreach ($item in $ExistingList) {
        if ($item -eq $Value) {
            return $true
        }
    }

    return $false
}
