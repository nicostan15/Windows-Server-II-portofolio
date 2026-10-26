#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Installeert IIS en publiceert een statische Hello World-pagina.
#>

param(
    [string]$DomainName = "WS26-JD.hogent"
)

$ErrorActionPreference = "Stop"

if ($env:COMPUTERNAME -ine "server1") {
    throw "Dit script is bedoeld voor server1."
}

$Result = Install-WindowsFeature `
    -Name Web-Server, Web-Static-Content, Web-Default-Doc, Web-Scripting-Tools `
    -IncludeManagementTools

if (-not $Result.Success) {
    throw "Installatie van IIS is mislukt."
}

Import-Module WebAdministration

$WebRoot = "C:\inetpub\wwwroot"

New-Item -Path $WebRoot -ItemType Directory -Force |
    Out-Null

$Html = @"
<!DOCTYPE html>
<html lang="nl">
<head>
    <meta charset="utf-8">
    <title>Intranet — Windows Server II</title>
</head>
<body>
    <h1>Hello World</h1>
    <p>Welkom op het intranet van $DomainName.</p>
    <p>Deze website draait op server1 en is geconfigureerd via PowerShell en Vagrant.</p>
</body>
</html>
"@

Set-Content `
    -Path "$WebRoot\default.htm" `
    -Value $Html `
    -Encoding UTF8

Set-ItemProperty `
    -Path "IIS:\Sites\Default Web Site" `
    -Name physicalPath `
    -Value $WebRoot

$DefaultDocumentFilter =
    "system.webServer/defaultDocument/files"

$DefaultDocuments = @(
    Get-WebConfigurationProperty `
        -PSPath "IIS:\Sites\Default Web Site" `
        -Filter $DefaultDocumentFilter `
        -Name "." |
        Select-Object -ExpandProperty Collection |
        ForEach-Object { $_.value }
)

if ("default.htm" -notin $DefaultDocuments) {
    Add-WebConfigurationProperty `
        -PSPath "IIS:\Sites\Default Web Site" `
        -Filter $DefaultDocumentFilter `
        -Name "." `
        -Value @{ value = "default.htm" }
}

$HttpBinding = Get-WebBinding `
    -Name "Default Web Site" `
    -Protocol http |
    Where-Object { $_.bindingInformation -eq "*:80:" }

if (-not $HttpBinding) {
    New-WebBinding `
        -Name "Default Web Site" `
        -Protocol http `
        -IPAddress "*" `
        -Port 80
}

Set-Service -Name W3SVC -StartupType Automatic
Start-Service -Name W3SVC

if ((Get-Website -Name "Default Web Site").State -ne "Started") {
    Start-Website -Name "Default Web Site"
}

$RuleName = "WS2-Server1-Intranet-HTTP"

Get-NetFirewallRule -Name $RuleName -ErrorAction SilentlyContinue |
    Remove-NetFirewallRule

New-NetFirewallRule `
    -Name $RuleName `
    -DisplayName "WS2 - Server1 - Intranet HTTP" `
    -Direction Inbound `
    -Action Allow `
    -Enabled True `
    -Profile Any `
    -Protocol TCP `
    -LocalPort 80 `
    -LocalAddress 192.168.26.10 `
    -RemoteAddress 192.168.26.0/24 |
    Out-Null

$Page = Invoke-WebRequest `
    -Uri "http://localhost/default.htm" `
    -UseBasicParsing `
    -TimeoutSec 30

if ($Page.StatusCode -ne 200 -or $Page.Content -notmatch "Hello World") {
    throw "De lokale IIS-controle is mislukt."
}

Write-Output "IIS is geïnstalleerd en de website draait."
Write-Output "Lokale controle: HTTP $($Page.StatusCode), Hello World gevonden."
Write-Output "Beoogde intranet-URL: http://intranet.$DomainName/"
Write-Output "Extern HTTP-verkeer toegestaan vanaf 192.168.26.0/24."