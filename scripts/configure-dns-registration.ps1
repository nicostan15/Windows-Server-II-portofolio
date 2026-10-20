<#
.SYNOPSIS
    Voorkomt ongewenste automatische DNS-clientregistratie.

.DESCRIPTION
    Mode Server:
        Schakelt registratie uit op de NAT-interface.
        Laat de Host-Only-instelling ongewijzigd.

    Mode Client:
        Schakelt registratie uit op alle actieve netwerkadapters.

    Wijzigt geen IP-adressen, DNS-serveradressen of gateways.
    Verwijdert geen bestaande DNS-records.
#>

param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("Server", "Client")]
    [string]$Mode
)

$ErrorActionPreference = "Stop"

$Adapters = @(
    Get-NetAdapter | Where-Object { $_.Status -eq "Up" }
)

if ($Adapters.Count -eq 0) {
    throw "Geen actieve netwerkadapters gevonden."
}

if ($Mode -eq "Client") {
    $TargetAdapters = $Adapters
} else {
    # In deze labomgeving heeft NAT een default gateway.
    # De Host-Only-interface heeft geen default gateway.
    $TargetAdapters = @(
        $Adapters | Where-Object {
            $Config = Get-NetIPConfiguration -InterfaceIndex $_.ifIndex
            $null -ne $Config.IPv4DefaultGateway
        }
    )

    if ($TargetAdapters.Count -ne 1) {
        throw "Verwacht precies een actieve NAT-interface met IPv4-default gateway."
    }
}

foreach ($Adapter in $TargetAdapters) {
    Set-DnsClient -InterfaceIndex $Adapter.ifIndex `
        -RegisterThisConnectionsAddress $false `
        -UseSuffixWhenRegistering $false

    Write-Host "DNS-clientregistratie uitgeschakeld: $($Adapter.Name)"
}

# Controleer of de wijziging effectief toegepast is.
foreach ($Adapter in $TargetAdapters) {
    $DnsClient = Get-DnsClient -InterfaceIndex $Adapter.ifIndex

    if ($DnsClient.RegisterThisConnectionsAddress) {
        throw "DNS-clientregistratie staat nog aan op $($Adapter.Name)."
    }
}

Get-DnsClient |
    Where-Object { $_.InterfaceIndex -in $Adapters.ifIndex } |
    Select-Object InterfaceAlias, InterfaceIndex,
        RegisterThisConnectionsAddress, UseSuffixWhenRegistering

Write-Host "`nDNS-clientregistratie ingesteld voor modus: $Mode" `
    -ForegroundColor Green