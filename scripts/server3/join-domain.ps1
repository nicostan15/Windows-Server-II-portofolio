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

# Interne interface herkennen aan het verwachte server3-adres.
$InternalAddresses = @(
    Get-NetIPAddress -AddressFamily IPv4 -PolicyStore ActiveStore |
        Where-Object { $_.IPAddress -eq "192.168.26.30" }
)

if ($InternalAddresses.Count -ne 1) {
    throw "Verwacht precies een interface met IP-adres 192.168.26.30; gevonden: $($InternalAddresses.Count)."
}

$InternalAddress = $InternalAddresses[0]

if ($InternalAddress.PrefixLength -ne 24) {
    throw "De interne interface heeft niet de verwachte prefix /24."
}

if ($InternalAddress.AddressState.ToString() -ne "Preferred") {
    throw "Het interne IP-adres is niet bruikbaar: $($InternalAddress.AddressState)."
}

$InternalIndex = $InternalAddress.InterfaceIndex

$InternalAdapter = Get-NetAdapter -InterfaceIndex $InternalIndex

if ($InternalAdapter.Status -ne "Up") {
    throw "De interne interface is niet actief."
}

$InternalDefaultRoutes = @(
    Get-NetRoute `
        -InterfaceIndex $InternalIndex `
        -AddressFamily IPv4 `
        -DestinationPrefix "0.0.0.0/0" `
        -PolicyStore ActiveStore
)

if ($InternalDefaultRoutes.Count -gt 0) {
    throw "De geselecteerde interne interface heeft een default-route. DNS wordt niet gewijzigd."
}

Write-Output (
    "Interne interface geselecteerd via IP-adres: {0}, index {1}" -f
    $InternalAdapter.Name, $InternalIndex
)

# Alleen op de gecontroleerde interne interface DNS instellen.
Set-DnsClientServerAddress `
    -InterfaceIndex $InternalIndex `
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