#Requires -RunAsAdministrator

param(
    [Parameter(Mandatory = $true)]
    [ValidateSet(
        "192.168.26.10",
        "192.168.26.20",
        "192.168.26.30"
    )]
    [string]$IPAddress
)

$ErrorActionPreference = "Stop"

$PrefixLength = 24
$NatGateway = "10.0.2.2"

$ExpectedAddresses = @{
    server1 = "192.168.26.10"
    server2 = "192.168.26.20"
    server3 = "192.168.26.30"
}

$Machine = $env:COMPUTERNAME.ToLowerInvariant()

if (-not $ExpectedAddresses.ContainsKey($Machine)) {
    throw "Dit script is uitsluitend bedoeld voor server1, server2 en server3."
}

if ($IPAddress -ne $ExpectedAddresses[$Machine]) {
    throw "Verkeerd IP-adres voor ${Machine}: verwacht $($ExpectedAddresses[$Machine])."
}

# ------------------------------------------------------------
# 1. Controleer de twee actieve netwerkadapters van dit lab.
# ------------------------------------------------------------

$Adapters = @(
    Get-NetAdapter |
        Where-Object { $_.Status -eq "Up" }
)

if ($Adapters.Count -ne 2) {
    throw "Verwacht precies twee actieve adapters; gevonden: $($Adapters.Count). Geen wijzigingen uitgevoerd."
}

# NAT herkennen aan de IPv4-default-route, niet aan de naam.
$DefaultRoutes = @(
    Get-NetRoute `
        -AddressFamily IPv4 `
        -DestinationPrefix "0.0.0.0/0" `
        -PolicyStore ActiveStore |
        Where-Object { $_.InterfaceIndex -in $Adapters.ifIndex }
)

$NatIndexes = @(
    $DefaultRoutes |
        Where-Object { $_.NextHop -eq $NatGateway } |
        Select-Object -ExpandProperty InterfaceIndex -Unique
)

if ($NatIndexes.Count -ne 1) {
    throw "Verwacht precies een NAT-interface met gateway $NatGateway. Geen wijzigingen uitgevoerd."
}

$NatIndex = $NatIndexes[0]

$InternalAdapters = @(
    $Adapters |
        Where-Object { $_.ifIndex -ne $NatIndex }
)

if ($InternalAdapters.Count -ne 1) {
    throw "Kan niet precies een interne interface selecteren. Geen wijzigingen uitgevoerd."
}

$InternalAdapter = $InternalAdapters[0]
$InternalIndex = $InternalAdapter.ifIndex

if ($DefaultRoutes.InterfaceIndex -contains $InternalIndex) {
    throw "De interne interface heeft een IPv4-default-route. Controleer dit handmatig; geen wijzigingen uitgevoerd."
}

Write-Output "Machine: $Machine"
Write-Output "NAT-interface beschermd: index $NatIndex"
Write-Output (
    "Interne interface: {0}, index {1}" -f
    $InternalAdapter.Name, $InternalIndex
)
Write-Output "Gewenste configuratie: $IPAddress/$PrefixLength"

# ------------------------------------------------------------
# 2. Controleer bestaande IPv4-configuratie.
# ------------------------------------------------------------

$AddressesElsewhere = @(
    Get-NetIPAddress -AddressFamily IPv4 -PolicyStore ActiveStore |
        Where-Object {
            $_.IPAddress -eq $IPAddress -and
            $_.InterfaceIndex -ne $InternalIndex
        }
)

if ($AddressesElsewhere.Count -gt 0) {
    throw "Het gewenste IP-adres staat al op een andere interface. Geen wijzigingen uitgevoerd."
}

$ExistingAddresses = @(
    Get-NetIPAddress `
        -InterfaceIndex $InternalIndex `
        -AddressFamily IPv4 `
        -PolicyStore ActiveStore `
        -ErrorAction Stop
)

# APIPA is toegestaan als beginstaat op een nieuwe machine.
# Andere afwijkende adressen worden niet automatisch verwijderd.
$UnexpectedAddresses = @(
    $ExistingAddresses |
        Where-Object {
            $_.IPAddress -ne $IPAddress -and
            $_.IPAddress -notlike "169.254.*"
        }
)

if ($UnexpectedAddresses.Count -gt 0) {
    $Found = $UnexpectedAddresses |
        ForEach-Object { "$($_.IPAddress)/$($_.PrefixLength)" }

    throw "Afwijkende interne IP-configuratie: $($Found -join ', '). Geen wijzigingen uitgevoerd."
}

$DesiredAddresses = @(
    $ExistingAddresses |
        Where-Object { $_.IPAddress -eq $IPAddress }
)

if ($DesiredAddresses.Count -gt 1) {
    throw "Het gewenste IP-adres is meermaals gevonden. Geen wijzigingen uitgevoerd."
}

if ($DesiredAddresses.Count -eq 1) {
    $Existing = $DesiredAddresses[0]

    if ($Existing.PrefixLength -ne $PrefixLength) {
        throw "Verkeerde prefix voor ${IPAddress}: $($Existing.PrefixLength), verwacht $PrefixLength."
    }

    if ($Existing.PrefixOrigin.ToString() -ne "Manual") {
        throw "Het gewenste adres is niet statisch ingesteld. Controleer dit handmatig."
    }

    if ($Existing.AddressState.ToString() -in @("Duplicate", "Invalid")) {
        throw "Het bestaande adres heeft een onbruikbare status: $($Existing.AddressState)."
    }

    $IPInterface = Get-NetIPInterface `
        -InterfaceIndex $InternalIndex `
        -AddressFamily IPv4

    if ($IPInterface.Dhcp.ToString() -ne "Disabled") {
        throw "Het statische adres bestaat, maar DHCP staat nog aan. Controleer dit handmatig."
    }

    Write-Output "Het juiste statische IP-adres bestaat al; geen wijziging nodig."
}
else {
    Write-Output "Statisch IP-adres instellen op de interne interface..."

    New-NetIPAddress `
        -InterfaceIndex $InternalIndex `
        -IPAddress $IPAddress `
        -PrefixLength $PrefixLength |
        Out-Null
}

# ------------------------------------------------------------
# 3. Wacht op een bruikbaar adres na duplicate address detection.
# ------------------------------------------------------------

$Deadline = (Get-Date).AddSeconds(60)
$Ready = $false

do {
    $CurrentAddress = Get-NetIPAddress `
        -InterfaceIndex $InternalIndex `
        -AddressFamily IPv4 `
        -PolicyStore ActiveStore |
        Where-Object { $_.IPAddress -eq $IPAddress }

    if ($CurrentAddress) {
        $State = $CurrentAddress.AddressState.ToString()

        if ($State -eq "Duplicate") {
            throw "Dubbel IP-adres gedetecteerd: $IPAddress. Los het adresconflict op."
        }

        if ($State -eq "Preferred") {
            $Ready = $true
            break
        }
    }

    Start-Sleep -Seconds 2
}
while ((Get-Date) -lt $Deadline)

if (-not $Ready) {
    throw "IP-adres $IPAddress is niet binnen 60 seconden bruikbaar geworden."
}

# ------------------------------------------------------------
# 4. Controleer actieve en persistente configuratie.
# ------------------------------------------------------------

$PersistentAddresses = @(
    Get-NetIPAddress `
        -InterfaceIndex $InternalIndex `
        -AddressFamily IPv4 `
        -PolicyStore PersistentStore |
        Where-Object {
            $_.IPAddress -eq $IPAddress -and
            $_.PrefixLength -eq $PrefixLength
        }
)

if ($PersistentAddresses.Count -ne 1) {
    throw "Het gewenste IP-adres is niet eenduidig opgeslagen in PersistentStore."
}

$FinalInterface = Get-NetIPInterface `
    -InterfaceIndex $InternalIndex `
    -AddressFamily IPv4

if ($FinalInterface.Dhcp.ToString() -ne "Disabled") {
    throw "DHCP staat nog aan op de interne serverinterface."
}

Write-Output "Controle actieve configuratie:"

Get-NetIPAddress `
    -InterfaceIndex $InternalIndex `
    -AddressFamily IPv4 `
    -PolicyStore ActiveStore |
    Select-Object InterfaceAlias, InterfaceIndex, IPAddress,
        PrefixLength, PrefixOrigin, AddressState |
    Format-Table -AutoSize |
    Out-String -Width 200 |
    Write-Output

Write-Output "PASS: interne statische IP-configuratie is correct en persistent."
Write-Output "NAT, DNS-serveradressen en DNS-registratie zijn niet gewijzigd."