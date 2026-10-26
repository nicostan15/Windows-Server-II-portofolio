#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Installeert de geselecteerde RSAT-tools op de Windows 11-client.

.DESCRIPTION
    Installeert alleen:
    - Active Directory DS/LDS Tools
    - DNS Server Tools
    - DHCP Server Tools
    - Group Policy Management Tools

    Reeds geinstalleerde onderdelen worden overgeslagen.
    Domeinjoin en remote beheer worden niet door dit script geconfigureerd.
#>

$ErrorActionPreference = "Stop"

if ($env:COMPUTERNAME -ine "client") {
    throw "Dit script is bedoeld voor de Windows 11-client."
}

Import-Module Dism

$Capabilities = @(
    "Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0"
    "Rsat.Dns.Tools~~~~0.0.1.0"
    "Rsat.DHCP.Tools~~~~0.0.1.0"
    "Rsat.GroupPolicy.Management.Tools~~~~0.0.1.0"
)

$RestartNeeded = $false

foreach ($CapabilityName in $Capabilities) {
    $Capability = Get-WindowsCapability `
        -Online `
        -Name $CapabilityName `
        -ErrorAction Stop

    if (-not $Capability) {
        throw "RSAT-onderdeel niet gevonden: $CapabilityName"
    }

    if ($Capability.State -eq "Installed") {
        Write-Output "Reeds geinstalleerd: $CapabilityName"
        continue
    }

    Write-Output "Installeren: $CapabilityName"

    $Result = Add-WindowsCapability `
        -Online `
        -Name $CapabilityName `
        -ErrorAction Stop

    if ($Result.RestartNeeded) {
        $RestartNeeded = $true
    }

    $UpdatedCapability = Get-WindowsCapability `
        -Online `
        -Name $CapabilityName `
        -ErrorAction Stop

    if ($UpdatedCapability.State -ne "Installed") {
        throw "Installatie niet voltooid voor $CapabilityName. Status: $($UpdatedCapability.State)"
    }

    Write-Output "Installatie geslaagd: $CapabilityName"
}

Write-Output ""
Write-Output "Controle geselecteerde RSAT-onderdelen:"

$InstalledCapabilities = foreach ($CapabilityName in $Capabilities) {
    Get-WindowsCapability `
        -Online `
        -Name $CapabilityName `
        -ErrorAction Stop
}

$InstalledCapabilities |
    Select-Object Name, State |
    Format-Table -AutoSize |
    Out-String -Width 200 |
    Write-Output

Write-Output "RSAT-installatie en statuscontrole voltooid."
Write-Output "Herstart vereist: $RestartNeeded"