<#
.SYNOPSIS
    Configureert server2 als secundaire DNS-server.

.DESCRIPTION
    Uitvoeren nadat het Host-Only IP is ingesteld.

    - Installeert de DNS-rol.
    - Schakelt DNS-registratie op de NAT-interface uit.
    - Laat DNS luisteren op het Host-Only IP.
    - Voegt gerichte DNS-firewallregels toe.
    - Configureert secundaire zones met server1 als master.
    - Vraagt een volledige zone transfer aan.

    Vereist:
    Server1 moet zone transfers naar 192.168.26.20 toestaan.
#>

param(
    [string]$PrimaryIP = "192.168.26.10",
    [string]$SecondaryIP = "192.168.26.20",
    [string]$DomainName = "WS26-JD.hogent"
)

$ErrorActionPreference = "Stop"

$Zones = @(
    $DomainName
    "26.168.192.in-addr.arpa"
    "_msdcs.$DomainName"
)

# ------------------------------------------------------------------
# 1. Controleer het Host-Only IP.
# ------------------------------------------------------------------

$InternalAddresses = @(
    Get-NetIPAddress -AddressFamily IPv4 |
        Where-Object { $_.IPAddress -eq $SecondaryIP }
)

if ($InternalAddresses.Count -ne 1) {
    throw "Verwacht precies een interface met Host-Only IP $SecondaryIP."
}

$InternalInterfaceIndex = $InternalAddresses[0].InterfaceIndex

# ------------------------------------------------------------------
# 2. Installeer de DNS-rol, niet AD DS.
# ------------------------------------------------------------------

if (-not (Get-WindowsFeature -Name DNS).Installed) {
    Write-Host "DNS-rol installeren..."

    $Install = Install-WindowsFeature -Name DNS -IncludeManagementTools

    if (-not $Install.Success) {
        throw "Installatie van de DNS-rol is mislukt."
    }

    Write-Host "DNS-rol geinstalleerd."
} else {
    Write-Host "DNS-rol is al aanwezig."
}

Import-Module DnsServer
Start-Service DNS

# ------------------------------------------------------------------
# 3. Schakel DNS-registratie op de NAT-interface uit.
# ------------------------------------------------------------------

$NatAdapters = @(
    Get-NetAdapter | Where-Object {
        $Config = Get-NetIPConfiguration -InterfaceIndex $_.ifIndex
        $null -ne $Config.IPv4DefaultGateway
    }
)

if ($NatAdapters.Count -ne 1) {
    throw "Verwacht precies een NAT-interface met default gateway."
}

Set-DnsClient -InterfaceIndex $NatAdapters[0].ifIndex `
    -RegisterThisConnectionsAddress $false

Write-Host "DNS-registratie uitgeschakeld op NAT-interface: $($NatAdapters[0].Name)"

# Gebruik server1 voor de eigen interne naamresolutie.
Set-DnsClientServerAddress -InterfaceIndex $InternalInterfaceIndex `
    -ServerAddresses $PrimaryIP

# ------------------------------------------------------------------
# 4. Laat de DNS-server luisteren op het Host-Only IP.
# ------------------------------------------------------------------

$DnsCmd = "$env:SystemRoot\System32\dnscmd.exe"

& $DnsCmd localhost /ResetListenAddresses $SecondaryIP

if ($LASTEXITCODE -ne 0) {
    throw "Instellen van het DNS-luisteradres is mislukt."
}

Restart-Service DNS

# Wacht op de DNS-beheerinterface, niet alleen op status Running.
$Deadline = (Get-Date).AddSeconds(120)
$Ready = $false
$LastDnsError = $null

do {
    try {
        $ExistingZones = @(Get-DnsServerZone -ErrorAction Stop)
        $Ready = $true
        break
    } catch {
        $LastDnsError = $_.Exception.Message
        Write-Host "DNS nog niet gereed; opnieuw proberen over 5 seconden..."
        Start-Sleep -Seconds 5
    }
} while ((Get-Date) -lt $Deadline)

if (-not $Ready) {
    throw "DNS niet gereed binnen 120 seconden. Laatste fout: $LastDnsError"
}

# ------------------------------------------------------------------
# 5. Voeg gerichte inkomende DNS-firewallregels toe.
# ------------------------------------------------------------------

foreach ($Protocol in @("TCP", "UDP")) {
    $RuleName = "WS2-DNS-$Protocol-HostOnly"

    $ExistingRule = Get-NetFirewallRule -Name $RuleName `
        -ErrorAction SilentlyContinue

    if (-not $ExistingRule) {
        New-NetFirewallRule -Name $RuleName `
            -DisplayName "WS2 DNS $Protocol via Host-Only" `
            -Direction Inbound `
            -Action Allow `
            -Protocol $Protocol `
            -LocalPort 53 `
            -LocalAddress $SecondaryIP `
            -RemoteAddress "192.168.26.0/24" `
            -Profile Any | Out-Null

        Write-Host "Firewallregel toegevoegd: $RuleName"
    } else {
        Write-Host "Firewallregel bestaat al: $RuleName"
    }
}

# ------------------------------------------------------------------
# 6. Controleer TCP-bereikbaarheid van de primaire DNS-server.
# ------------------------------------------------------------------

Write-Host "Verbinding met primaire DNS-server controleren..."

$PrimaryReachable = Test-NetConnection -ComputerName $PrimaryIP `
    -Port 53 -InformationLevel Quiet -WarningAction SilentlyContinue

if (-not $PrimaryReachable) {
    throw "Server1 ($PrimaryIP) is niet bereikbaar op TCP-poort 53. Controleer server1 en de firewall."
}

# ------------------------------------------------------------------
# 7. Configureer de secundaire zones.
# ------------------------------------------------------------------

foreach ($Zone in $Zones) {
    $Existing = $ExistingZones |
        Where-Object { $_.ZoneName -ieq $Zone }

    if (-not $Existing) {
        Add-DnsServerSecondaryZone -Name $Zone `
            -ZoneFile "$Zone.dns" `
            -MasterServers $PrimaryIP

        Write-Host "Secundaire zone aangemaakt: $Zone"
    } elseif ($Existing.ZoneType -ne "Secondary") {
        throw "Zone $Zone bestaat maar is niet Secondary. Niet automatisch overschreven."
    } else {
        Set-DnsServerSecondaryZone -Name $Zone `
            -MasterServers $PrimaryIP

        Write-Host "Master gecontroleerd voor bestaande secundaire zone: $Zone"
    }

    Start-DnsServerZoneTransfer -Name $Zone -FullTransfer

    Write-Host "Volledige zone transfer aangevraagd: $Zone"
}

Write-Host "`nConfiguratie van secundaire DNS voltooid." -ForegroundColor Green
Write-Host "Controleer hierna of de zones en records daadwerkelijk geladen zijn."