#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$global:GenesisLogFile    = $null
$global:GenesisLogInitialized = $false

function Write-GenesisLog {
    param(
        [Parameter(Mandatory)]
        [ValidateSet('DEBUG', 'INFO', 'WARN', 'ERROR')]
        [string] $Level,

        [Parameter(Mandatory)]
        [string] $Message,

        [switch] $NoConsole
    )

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logLine   = "[$timestamp] [$Level] $Message"

    if ($global:GenesisLogInitialized -and $global:GenesisLogFile) {
        Add-Content -LiteralPath $global:GenesisLogFile -Value $logLine -Encoding ASCII
    }

    if (-not $NoConsole) {
        $color = switch ($Level) {
            'DEBUG' { 'DarkGray' }
            'INFO'  { 'Cyan'     }
            'WARN'  { 'Yellow'   }
            'ERROR' { 'Red'      }
        }
        Write-Host $logLine -ForegroundColor $color
    }
}

function Write-GenesisSection {
    param(
        [Parameter(Mandatory)] [string] $Title
    )

    $border = '-' * 60
    $line   = "  >> $Title"

    Write-Host ''                -ForegroundColor DarkGray
    Write-Host $border           -ForegroundColor DarkGray
    Write-Host $line             -ForegroundColor White
    Write-Host $border           -ForegroundColor DarkGray
    Write-Host ''

    if ($global:GenesisLogInitialized -and $global:GenesisLogFile) {
        $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        Add-Content -LiteralPath $global:GenesisLogFile -Value '' -Encoding ASCII
        Add-Content -LiteralPath $global:GenesisLogFile -Value "[$ts] [SECTION] $Title" -Encoding ASCII
    }
}