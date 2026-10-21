#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Zorgt dat server1 het rootcertificaat van de Enterprise Root CA
    vertrouwt via Active Directory autoenrollment.
#>

param(
    [string]$CACommonName = "WS26-JD-Root-CA"
)

$ErrorActionPreference = "Stop"

Write-Output "Root-CA-vertrouwen controleren op server1..."

$Deadline = (Get-Date).AddMinutes(3)
$RootCertificate = $null

while ((Get-Date) -lt $Deadline) {
    & certutil.exe -pulse | Out-Null

    $RootCertificate = Get-ChildItem Cert:\LocalMachine\Root |
        Where-Object { $_.Subject -like "*$CACommonName*" } |
        Select-Object -First 1

    if ($RootCertificate) {
        break
    }

    Write-Output "Rootcertificaat nog niet ontvangen; opnieuw proberen over 15 seconden..."
    Start-Sleep -Seconds 15
}

if (-not $RootCertificate) {
    throw "Rootcertificaat '$CACommonName' is niet binnen drie minuten ontvangen."
}

Write-Output "Rootcertificaat aanwezig in Trusted Root:"

$RootCertificate |
    Format-List Subject, Thumbprint, NotAfter |
    Out-String -Width 200 |
    Write-Output