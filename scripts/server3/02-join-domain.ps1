#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Voegt server3 toe aan het domein.

.DESCRIPTION
    Controleert eerst het bestaande domeinlidmaatschap.
    Voegt server3 indien nodig toe aan de Servers-OU.
    Vagrant verzorgt daarna de herstart.
#>

param(
    [string]$DomainName = "WS26-JD.hogent",

    [string]$OUPath = "OU=Servers,DC=WS26-JD,DC=hogent",

    [string]$DomainAdminUser = "WS26-JD\Administrator",

    [string]$DomainAdminPassword
)

$ErrorActionPreference = "Stop"

if ($env:COMPUTERNAME -ine "server3") {
    throw "Dit script is bedoeld voor server3, niet voor $env:COMPUTERNAME."
}

$Computer = Get-CimInstance -ClassName Win32_ComputerSystem

if ($Computer.PartOfDomain) {
    if ($Computer.Domain -ine $DomainName) {
        throw "Server3 is al lid van een ander domein: $($Computer.Domain)."
    }

    Write-Output "Server3 is al lid van $DomainName. Domeinjoin overslaan."
    return
}

if ([string]::IsNullOrWhiteSpace($DomainAdminPassword)) {
    throw "Geen domeinwachtwoord opgegeven. Stel WS2_DOMAIN_ADMIN_PASSWORD in op de host."
}

$SecurePassword = ConvertTo-SecureString `
    -String $DomainAdminPassword `
    -AsPlainText `
    -Force

$Credential = [System.Management.Automation.PSCredential]::new(
    $DomainAdminUser,
    $SecurePassword
)

# Interne DNS-servers instellen vóór de domeinjoin.
Set-DnsClientServerAddress `
    -InterfaceAlias "Ethernet 2" `
    -ServerAddresses "192.168.26.10", "192.168.26.20"

Write-Output "Server3 toevoegen aan domein $DomainName..."

$Result = Add-Computer `
    -DomainName $DomainName `
    -OUPath $OUPath `
    -Credential $Credential `
    -PassThru `
    -Verbose `
    -ErrorAction Stop

if (-not $Result.HasSucceeded) {
    throw "De domeinjoin is niet geslaagd."
}

Write-Output "Domeinjoin geslaagd. Vagrant moet server3 nu herstarten."