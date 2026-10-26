<#
.SYNOPSIS
    Configureert de primaire DNS-server op server1.

.DESCRIPTION
    Uitvoeren na domeincontroller-promotie en reboot.

    - Controleert DNS-rol en AD-geintegreerde zones.
    - Wacht tot DNS-zones beschikbaar zijn.
    - Schakelt DNS-clientregistratie op NAT uit.
    - Laat DNS luisteren op het Host-Only IP.
    - Ruimt A-records met de huidige NAT-IP-adressen op.
    - Maakt de reverse lookup zone indien nodig aan.
    - Controleert A- en PTR-records onafhankelijk.
    - Configureert gerichte DNS-firewallregels.
    - Configureert NS-records, zone transfers en notify voor server2.
    - Maakt het intranet-A-record aan indien nodig.
    - Controleert bestaande intranetrecords op conflicten.

    Netwerk: 192.168.26.0/24.
#>

param(
    [string]$Server1IP = "192.168.26.10",
    [string]$Server2IP = "192.168.26.20"
)

$ErrorActionPreference = "Stop"

Import-Module ActiveDirectory
Import-Module DnsServer

$NetworkId = "192.168.26.0/24"
$ReverseZone = "26.168.192.in-addr.arpa"

# ------------------------------------------------------------------
# Helper: wacht tot de opgegeven AD-geintegreerde zones geladen zijn.
# ------------------------------------------------------------------
function Wait-PrimaryDnsZones {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$ZoneNames,

        [int]$TimeoutSeconds = 180
    )

    $Deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $LastDnsError = "Nog geen resultaat."

    do {
        try {
            $LoadedZones = @(Get-DnsServerZone -ErrorAction Stop)

            $MissingZones = @(
                foreach ($ZoneName in $ZoneNames) {
                    $Found = $LoadedZones | Where-Object {
                        $_.ZoneName -ieq $ZoneName -and
                        $_.ZoneType -eq "Primary" -and
                        $_.IsDsIntegrated
                    }

                    if (-not $Found) {
                        $ZoneName
                    }
                }
            )

            if ($MissingZones.Count -eq 0) {
                Write-Host "DNS gereed: vereiste AD-zones zijn geladen."
                return
            }

            $LastDnsError = "Zones nog niet gereed: $($MissingZones -join ', ')"
        } catch {
            $LastDnsError = $_.Exception.Message
        }

        Write-Host "DNS-zones nog niet gereed; opnieuw proberen over 5 seconden..."
        Start-Sleep -Seconds 5

    } while ((Get-Date) -lt $Deadline)

    throw "DNS niet gereed binnen $TimeoutSeconds seconden. Laatste melding: $LastDnsError"
}

# ------------------------------------------------------------------
# 1. Controleer DNS-rol en Host-Only IP.
# ------------------------------------------------------------------
if (-not (Get-WindowsFeature -Name DNS).Installed) {
    throw "DNS-rol ontbreekt. Voer eerst promote-dc.ps1 uit."
}

$InternalAddresses = @(
    Get-NetIPAddress -AddressFamily IPv4 |
        Where-Object { $_.IPAddress -eq $Server1IP }
)

if ($InternalAddresses.Count -ne 1) {
    throw "Verwacht precies een interface met Host-Only IP $Server1IP."
}

Start-Service DNS

# Bepaal de domeinnaam lokaal, zonder eerst een AD-query uit te voeren.
$ComputerSystem = Get-CimInstance -ClassName Win32_ComputerSystem

if ($ComputerSystem.DomainRole -notin @(4, 5)) {
    throw "Dit script moet op de domeincontroller worden uitgevoerd."
}

$ForwardZone = $ComputerSystem.Domain
$MsdcsZone = "_msdcs.$ForwardZone"
$RequiredAdZones = @($ForwardZone, $MsdcsZone)

Wait-PrimaryDnsZones -ZoneNames $RequiredAdZones

# Controleer daarna ook de AD-domeinnaam.
$Domain = Get-ADDomain -Server $env:COMPUTERNAME

if ($Domain.DNSRoot -ine $ForwardZone) {
    throw "AD-domeinnaam komt niet overeen met de lokale domeinconfiguratie."
}

Write-Host "AD-forward zone aanwezig: $ForwardZone"

# ------------------------------------------------------------------
# 2. Identificeer NAT en schakel clientregistratie uit.
# ------------------------------------------------------------------
$NatAdapters = @(
    Get-NetAdapter |
        Where-Object { $_.Status -eq "Up" } |
        Where-Object {
            $Config = Get-NetIPConfiguration -InterfaceIndex $_.ifIndex
            $null -ne $Config.IPv4DefaultGateway
        }
)

if ($NatAdapters.Count -ne 1) {
    throw "Verwacht precies een actieve NAT-interface met default gateway."
}

$NatAdapter = $NatAdapters[0]

$NatIPs = @(
    Get-NetIPAddress -InterfaceIndex $NatAdapter.ifIndex `
        -AddressFamily IPv4 |
        Select-Object -ExpandProperty IPAddress
)

Set-DnsClient -InterfaceIndex $NatAdapter.ifIndex `
    -RegisterThisConnectionsAddress $false `
    -UseSuffixWhenRegistering $false

Write-Host "DNS-clientregistratie uit op NAT: $($NatAdapter.Name)"

# ------------------------------------------------------------------
# 3. Laat DNS luisteren op het Host-Only IP.
# ------------------------------------------------------------------
$DnsCmd = "$env:SystemRoot\System32\dnscmd.exe"

& $DnsCmd localhost /ResetListenAddresses $Server1IP

if ($LASTEXITCODE -ne 0) {
    throw "Instellen van het DNS-luisteradres is mislukt."
}

Restart-Service DNS

Wait-PrimaryDnsZones -ZoneNames $RequiredAdZones

# ------------------------------------------------------------------
# 4. Ruim huidige NAT-A-records op in primaire forward zones.
# ------------------------------------------------------------------
$PrimaryForwardZones = @(
    Get-DnsServerZone | Where-Object {
        $_.ZoneType -eq "Primary" -and
        -not $_.IsReverseLookupZone
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

# ------------------------------------------------------------------
# 5. Maak de reverse zone aan indien nodig.
# ------------------------------------------------------------------
$ExistingReverse = Get-DnsServerZone |
    Where-Object { $_.ZoneName -ieq $ReverseZone }

if (-not $ExistingReverse) {
    Add-DnsServerPrimaryZone -NetworkId $NetworkId `
        -ReplicationScope Domain `
        -DynamicUpdate Secure

    Write-Host "Reverse zone aangemaakt: $ReverseZone"

} elseif ($ExistingReverse.ZoneType -ne "Primary" -or
          -not $ExistingReverse.IsDsIntegrated) {

    throw "Bestaande reverse zone is niet AD-geintegreerd en Primary."
} else {
    Write-Host "Reverse zone bestaat reeds: $ReverseZone"
}

# ------------------------------------------------------------------
# 6. Controleer A- en PTR-records onafhankelijk.
# ------------------------------------------------------------------
$Servers = @(
    @{ Name = "server1"; IP = $Server1IP }
    @{ Name = "server2"; IP = $Server2IP }
    @{ Name = "server3"; IP = "192.168.26.30" }
)

foreach ($Server in $Servers) {
    $Name = $Server.Name
    $IP = $Server.IP
    $Fqdn = "$Name.$ForwardZone."
    $PtrName = ($IP -split "\.")[-1]

    # A-records controleren.
    $ARecords = @(
        Get-DnsServerResourceRecord -ZoneName $ForwardZone |
            Where-Object {
                $_.HostName -ieq $Name -and
                $_.RecordType -eq "A"
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
            -Name $Name `
            -IPv4Address $IP

        Write-Host "A-record aangemaakt: $Name -> $IP"
    } else {
        Write-Host "A-record correct: $Name -> $IP"
    }

    # PTR-records afzonderlijk controleren.
    $PtrRecords = @(
        Get-DnsServerResourceRecord -ZoneName $ReverseZone |
            Where-Object {
                $_.HostName -eq $PtrName -and
                $_.RecordType -eq "PTR"
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
            -Name $PtrName `
            -PtrDomainName $Fqdn

        Write-Host "PTR-record aangemaakt: $IP -> $Fqdn"
    } else {
        Write-Host "PTR-record correct: $IP -> $Fqdn"
    }
}

# ------------------------------------------------------------------
# 7. Maak gerichte DNS-firewallregels aan of herstel ze.
# ------------------------------------------------------------------
foreach ($Protocol in @("TCP", "UDP")) {
    $RuleName = "WS2-DNS-$Protocol-HostOnly"
    $RuleDisplayName = "WS2 DNS $Protocol via Host-Only"

    # Alleen parameters die bij New en Set dezelfde functie hebben.
    $RuleSettings = @{
        Direction     = "Inbound"
        Action        = "Allow"
        Enabled       = "True"
        Protocol      = $Protocol
        LocalPort     = 53
        LocalAddress  = $Server1IP
        RemoteAddress = $NetworkId
        Profile       = "Any"
    }

    $ExistingRule = Get-NetFirewallRule -Name $RuleName `
        -ErrorAction SilentlyContinue

    if ($ExistingRule) {
        Set-NetFirewallRule -Name $RuleName `
            -NewDisplayName $RuleDisplayName `
            @RuleSettings

        Write-Host "Firewallregel gecontroleerd: $RuleName"
    } else {
        New-NetFirewallRule -Name $RuleName `
            -DisplayName $RuleDisplayName `
            @RuleSettings |
            Out-Null

        Write-Host "Firewallregel aangemaakt: $RuleName"
    }
}

# ------------------------------------------------------------------
# 8. Configureer server2 als naamserver en transferdoel.
# ------------------------------------------------------------------
$Server2Fqdn = "server2.$ForwardZone."

$TransferZones = @(
    $ForwardZone
    $ReverseZone
    $MsdcsZone
)

foreach ($ZoneName in $TransferZones) {
    $ExistingNS = Get-DnsServerResourceRecord -ZoneName $ZoneName |
        Where-Object {
            $_.RecordType -eq "NS" -and
            $_.HostName -eq "@" -and
            $_.RecordData.NameServer.TrimEnd(".") -ieq
                $Server2Fqdn.TrimEnd(".")
        }

    if (-not $ExistingNS) {
        Add-DnsServerResourceRecord -ZoneName $ZoneName `
            -NS `
            -Name "@" `
            -NameServer $Server2Fqdn

        Write-Host "NS-record toegevoegd: server2 in $ZoneName"
    } else {
        Write-Host "NS-record server2 aanwezig in $ZoneName"
    }

    Set-DnsServerPrimaryZone -Name $ZoneName `
        -SecureSecondaries TransferToSecureServers `
        -SecondaryServers $Server2IP `
        -Notify NotifyServers `
        -NotifyServers $Server2IP

    Write-Host "Zone transfer en notify ingesteld: $ZoneName -> $Server2IP"
}

# ------------------------------------------------------------------
# 9. Maak het intranet-A-record aan of controleer het bestaande record.
# ------------------------------------------------------------------
$IntranetName = "intranet"
$IntranetFqdn = "$IntranetName.$ForwardZone"

$ExistingIntranetRecords = @(
    Get-DnsServerResourceRecord -ZoneName $ForwardZone `
        -ErrorAction Stop |
        Where-Object { $_.HostName -ieq $IntranetName }
)

$ExistingIntranetARecords = @(
    $ExistingIntranetRecords |
        Where-Object { $_.RecordType -eq "A" }
)

$ConflictingIntranetRecords = @(
    $ExistingIntranetRecords |
        Where-Object { $_.RecordType -in @("CNAME", "AAAA") }
)

if ($ConflictingIntranetRecords.Count -gt 0) {
    throw "Er bestaat al een CNAME- of AAAA-record voor $IntranetFqdn. Controleer dit eerst."
}

if ($ExistingIntranetARecords.Count -eq 0) {
    Add-DnsServerResourceRecordA -ZoneName $ForwardZone `
        -Name $IntranetName `
        -IPv4Address $Server1IP `
        -ErrorAction Stop

    Write-Host "Intranetrecord aangemaakt: $IntranetFqdn -> $Server1IP"
} elseif (
    $ExistingIntranetARecords.Count -ne 1 -or
    $ExistingIntranetARecords[0].RecordData.IPv4Address.IPAddressToString -ne $Server1IP
) {
    throw "Het bestaande A-record voor $IntranetFqdn wijkt af van $Server1IP. Controleer dit eerst."
} else {
    Write-Host "Intranetrecord correct: $IntranetFqdn -> $Server1IP"
}

Write-Host "`nPrimaire DNS-configuratie voltooid." -ForegroundColor Green