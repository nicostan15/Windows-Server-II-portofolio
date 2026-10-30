#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Vernieuwt het computerbeleid en controleert of server1
    het rootcertificaat van de Enterprise Root CA vertrouwt.
#>

param(
    [string]$CACommonName = "WS26-JD-Root-CA"
)

$ErrorActionPreference = "Stop"

Write-Output "Computerbeleid vernieuwen voor Root-CA-vertrouwen..."

& gpupdate.exe /target:computer /force /wait:120

if ($LASTEXITCODE -ne 0) {
    throw "Vernieuwen van computerbeleid is mislukt. Exitcode: $LASTEXITCODE"
}

Write-Output "Root-CA-vertrouwen controleren op server1..."

$Deadline = (Get-Date).AddMinutes(3)
$RootCertificate = $null

while ((Get-Date) -lt $Deadline) {
    & certutil.exe -pulse | Out-Null

    $Now = Get-Date

    $RootCertificate = Get-ChildItem Cert:\LocalMachine\Root |
        Where-Object {
            $_.Subject -like "*$CACommonName*" -and
            $_.NotBefore -le $Now -and
            $_.NotAfter -gt $Now
        } |
        Sort-Object NotAfter -Descending |
        Select-Object -First 1

    if ($RootCertificate) {
        break
    }

    Write-Output "Rootcertificaat nog niet ontvangen; opnieuw proberen over 15 seconden..."
    Start-Sleep -Seconds 15
}

if (-not $RootCertificate) {
    throw "Rootcertificaat '$CACommonName' is niet binnen drie minuten na de beleidsvernieuwing gevonden."
}

Write-Output "Rootcertificaat aanwezig in Trusted Root:"

$RootCertificate |
    Format-List Subject, Thumbprint, NotAfter |
    Out-String -Width 200 |
    Write-Output