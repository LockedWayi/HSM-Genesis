#Requires -Version 5.1
#Requires -RunAsAdministrator

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

. "$PSScriptRoot\core\Logger.ps1"
. "$PSScriptRoot\core\Validator.ps1"
. "$PSScriptRoot\core\StepTracker.ps1"
. "$PSScriptRoot\core\Cleanup.ps1"
. "$PSScriptRoot\core\MenuNavigation.ps1"
. "$PSScriptRoot\core\Engine.ps1"

Start-GenesisEngine