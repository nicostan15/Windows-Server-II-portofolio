<#
.SYNOPSIS
    Configureert de primaire DNS-server op server1.

.DESCRIPTION
    Uitvoeren na de domeincontroller-promotie en reboot.

    - Controleert DNS-rol en bestaande AD-forward zone.
    - Schakelt DNS-clientregistratie uit op de NAT-interface.
    - Laat DNS luisteren op het Host-Only IP.
    - Verwijdert A-records met de huidige NAT-IP-adressen.
    - Maakt de reverse lookup zone indien nodig aan.
    - Controleert A- en PTR-records onafhankelijk.
    - Bereidt zone transfers naar server2 voor.

    Netwerk: 192.168.26.0/24.
#>

param(
    [string]$Server1IP = "192.168.26.10",
    [string]$Server2IP = "192.168.26.20"
)

$ErrorActionPreference = "Stop"

Import-Module ActiveDirectory
Import-Module DnsServer

$ForwardZone = (Get-ADDomain).DNSRoot
$NetworkId = "192.168.26.0/24"
$ReverseZone = "26.168.192.in-addr.arpa"

$Servers = @(
    @{ Name = "server1"; IP = $Server1IP }
    @{ Name = "server2"; IP = $Server2IP }
    @{ Name = "server3"; IP = "192.168.26.30" }
)

# 1. Controleer de vereiste rol en forward zone.
if (-not (Get-WindowsFeature -Name DNS).Installed) {
    throw "DNS-rol ontbreekt. Voer eerst promote-dc.ps1 uit."
}

Start-Service DNS

$Forward = Get-DnsServerZone -Name $ForwardZone

if ($Forward.ZoneType -ne "Primary" -or -not $Forward.IsDsIntegrated) {
    throw "De forward zone $ForwardZone moet AD-geintegreerd en Primary zijn."
}

Write-Host "AD-forward zone aanwezig: $ForwardZone"

# 2. Identificeer NAT via de default gateway.
$NatAdapters = @(
    Get-NetAdapter | Where-Object {
        $Config = Get-NetIPConfiguration -InterfaceIndex $_.ifIndex
        $null -ne $Config.IPv4DefaultGateway
    }
)

if ($NatAdapters.Count -ne 1) {
    throw "Verwacht precies een NAT-interface met default gateway."
}

$NatAdapter = $NatAdapters[0]

$NatIPs = @(
    Get-NetIPAddress -InterfaceIndex $NatAdapter.ifIndex `
        -AddressFamily IPv4 |
        Select-Object -ExpandProperty IPAddress
)

Set-DnsClient -InterfaceIndex $NatAdapter.ifIndex `
    -RegisterThisConnectionsAddress $false

Write-Host "DNS-clientregistratie uit op NAT: $($NatAdapter.Name)"

# 3. Laat DNS uitsluitend luisteren op het Host-Only IP.
if (-not (Get-NetIPAddress -AddressFamily IPv4 |
    Where-Object { $_.IPAddress -eq $Server1IP })) {
    throw "Host-Only IP $Server1IP staat niet op deze server."
}

$DnsCmd = "$env:SystemRoot\System32\dnscmd.exe"

& $DnsCmd localhost /ResetListenAddresses $Server1IP

if ($LASTEXITCODE -ne 0) {
    throw "Instellen van het DNS-luisteradres is mislukt."
}

Restart-Service DNS

# Running betekent niet noodzakelijk dat de DNS-zones al geladen zijn.
# Wacht maximaal 180 seconden tot de AD-forward zone beschikbaar is.
$Deadline = (Get-Date).AddSeconds(180)
$DnsReady = $false
$LastDnsError = $null

do {
    try {
        $LoadedZones = @(Get-DnsServerZone -ErrorAction Stop)

        $LoadedForwardZone = $LoadedZones |
            Where-Object {
                $_.ZoneName -ieq $ForwardZone -and
                $_.ZoneType -eq "Primary" -and
                $_.IsDsIntegrated
            }

        if ($LoadedForwardZone) {
            $DnsReady = $true
            break
        }

        $LastDnsError = "Forward zone $ForwardZone is nog niet geladen."
    } catch {
        $LastDnsError = $_.Exception.Message
    }

    Write-Host "DNS-zones nog niet beschikbaar; opnieuw proberen over 5 seconden..."
    Start-Sleep -Seconds 5

} while ((Get-Date) -lt $Deadline)

if (-not $DnsReady) {
    throw "DNS-zones niet beschikbaar binnen 180 seconden. Laatste melding: $LastDnsError"
}

Write-Host "DNS gereed: AD-forward zone $ForwardZone is geladen." `
    -ForegroundColor Green

# 4. Ruim NAT-A-records op in alle lokale primaire forward zones.
$PrimaryForwardZones = @(
    Get-DnsServerZone | Where-Object {
        $_.ZoneType -eq "Primary" -and -not $_.IsReverseLookupZone
    }
)

foreach ($Zone in $PrimaryForwardZones) {
    $Records = @(Get-DnsServerResourceRecord -ZoneName $Zone.ZoneName)

    foreach ($Record in $Records) {
        if ($Record.RecordType -eq "A" -and
            $Record.RecordData.IPv4Address.IPAddressToString -in $NatIPs) {

            Remove-DnsServerResourceRecord -ZoneName $Zone.ZoneName `
                -InputObject $Record -Force

            Write-Host "NAT-A-record verwijderd: $($Record.HostName) in $($Zone.ZoneName)"
        }
    }
}

# 5. Reverse lookup zone aanmaken indien nodig.
$ExistingReverse = Get-DnsServerZone |
    Where-Object { $_.ZoneName -eq $ReverseZone }

if (-not $ExistingReverse) {
    Add-DnsServerPrimaryZone -NetworkId $NetworkId `
        -ReplicationScope Domain -DynamicUpdate Secure

    Write-Host "Reverse zone aangemaakt: $ReverseZone"
} elseif ($ExistingReverse.ZoneType -ne "Primary" -or
          -not $ExistingReverse.IsDsIntegrated) {
    throw "De bestaande reverse zone is niet AD-geintegreerd en Primary."
} else {
    Write-Host "Reverse zone bestaat reeds: $ReverseZone"
}

# 6. A- en PTR-records onafhankelijk controleren/herstellen.
foreach ($Server in $Servers) {
    $Name = $Server.Name
    $IP = $Server.IP
    $Fqdn = "$Name.$ForwardZone."
    $PtrName = ($IP -split "\.")[-1]

    # A-records voor deze server: verkeerde adressen verwijderen.
    $ARecords = @(
        Get-DnsServerResourceRecord -ZoneName $ForwardZone |
            Where-Object {
                $_.HostName -eq $Name -and $_.RecordType -eq "A"
            }
    )

    foreach ($Record in $ARecords) {
        if ($Record.RecordData.IPv4Address.IPAddressToString -ne $IP) {
            Remove-DnsServerResourceRecord -ZoneName $ForwardZone `
                -InputObject $Record -Force

            Write-Host "Verkeerd A-record verwijderd voor $Name"
        }
    }

    $CorrectA = @(
        $ARecords | Where-Object {
            $_.RecordData.IPv4Address.IPAddressToString -eq $IP
        }
    )

    if ($CorrectA.Count -eq 0) {
        Add-DnsServerResourceRecordA -ZoneName $ForwardZone `
            -Name $Name -IPv4Address $IP

        Write-Host "A-record aangemaakt: $Name -> $IP"
    } else {
        Write-Host "A-record correct: $Name -> $IP"
    }

    # PTR-records: apart controleren, ook wanneer A al bestond.
    $PtrRecords = @(
        Get-DnsServerResourceRecord -ZoneName $ReverseZone |
            Where-Object {
                $_.HostName -eq $PtrName -and $_.RecordType -eq "PTR"
            }
    )

    foreach ($Record in $PtrRecords) {
        if ($Record.RecordData.PtrDomainName.TrimEnd(".") -ine
            $Fqdn.TrimEnd(".")) {

            Remove-DnsServerResourceRecord -ZoneName $ReverseZone `
                -InputObject $Record -Force

            Write-Host "Verkeerd PTR-record verwijderd voor $IP"
        }
    }

    $CorrectPtr = @(
        $PtrRecords | Where-Object {
            $_.RecordData.PtrDomainName.TrimEnd(".") -ieq
                $Fqdn.TrimEnd(".")
        }
    )

    if ($CorrectPtr.Count -eq 0) {
        Add-DnsServerResourceRecordPtr -ZoneName $ReverseZone `
            -Name $PtrName -PtrDomainName $Fqdn

        Write-Host "PTR-record aangemaakt: $IP -> $Fqdn"
    } else {
        Write-Host "PTR-record correct: $IP -> $Fqdn"
    }
}

# 7. NS-record server2 en beperkte zone transfers.
$Server2Fqdn = "server2.$ForwardZone."

foreach ($ZoneName in @($ForwardZone, $ReverseZone)) {
    $ExistingNS = Get-DnsServerResourceRecord -ZoneName $ZoneName |
        Where-Object {
            $_.RecordType -eq "NS" -and
            $_.HostName -eq "@" -and
            $_.RecordData.NameServer.TrimEnd(".") -ieq
                $Server2Fqdn.TrimEnd(".")
        }

    if (-not $ExistingNS) {
        Add-DnsServerResourceRecord -ZoneName $ZoneName `
            -NS -Name "@" -NameServer $Server2Fqdn

        Write-Host "NS-record toegevoegd: server2 in $ZoneName"
    }

    Set-DnsServerPrimaryZone -Name $ZoneName `
        -SecureSecondaries TransferToSecureServers `
        -SecondaryServers $Server2IP `
        -Notify NotifyServers `
        -NotifyServers $Server2IP
}

Write-Host "`nPrimaire DNS-configuratie voltooid." -ForegroundColor Green