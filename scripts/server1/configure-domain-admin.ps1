#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Stelt het domein-Administratorwachtwoord expliciet in voor het lab.

.DESCRIPTION
    Uitvoeren op server1 na de domeincontroller-promotie en herstart.
    Bij iedere uitvoering wordt het opgegeven wachtwoord opnieuw ingesteld.
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$DomainAdminPassword
)

$ErrorActionPreference = "Stop"

if ($env:COMPUTERNAME -ine "server1") {
    throw "Dit script is bedoeld voor server1."
}

Import-Module ActiveDirectory

$Domain = Get-ADDomain -ErrorAction Stop

if ($Domain.DNSRoot -ine "WS26-JD.hogent") {
    throw "Onverwacht domein: $($Domain.DNSRoot)"
}

# Zoek de ingebouwde domein-Administrator via de domein-SID.
$AdministratorSID = "$($Domain.DomainSID.Value)-500"

$Administrator = Get-ADUser `
    -Identity $AdministratorSID `
    -ErrorAction Stop

if (-not $Administrator.Enabled) {
    throw "De domein-Administrator is uitgeschakeld. Controleer dit eerst."
}

$SecurePassword = ConvertTo-SecureString `
    -String $DomainAdminPassword `
    -AsPlainText `
    -Force

Set-ADAccountPassword `
    -Identity $Administrator `
    -Reset `
    -NewPassword $SecurePassword `
    -ErrorAction Stop

Set-ADUser `
    -Identity $Administrator `
    -ChangePasswordAtLogon $false `
    -ErrorAction Stop

Write-Output "Domein-Administratorwachtwoord ingesteld voor $($Administrator.SamAccountName)."