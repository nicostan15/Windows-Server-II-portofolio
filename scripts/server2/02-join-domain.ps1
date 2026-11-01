#Requires -RunAsAdministrator

param(
    [string]$DomainName = "WS26-JD.hogent",
    [string]$OUPath = "OU=Servers,DC=WS26-JD,DC=hogent",
    [string]$DomainAdminUser = "WS26-JD\Administrator",

    [Parameter(Mandatory = $true)]
    [string]$DomainAdminPassword
)

$ErrorActionPreference = "Stop"

if ($env:COMPUTERNAME -ine "server2") {
    throw "Dit script is bedoeld voor server2."
}

# DNS ook controleren/herstellen als server2 al domeinlid is.
$InternalAddresses = @(
    Get-NetIPAddress -AddressFamily IPv4 |
        Where-Object {
            $_.IPAddress -eq "192.168.26.20"
        }
)

if ($InternalAddresses.Count -ne 1) {
    throw "Verwacht precies een interne interface met IP 192.168.26.20."
}

$InterfaceIndex = $InternalAddresses[0].InterfaceIndex

Write-Output "Interne DNS op server2 instellen: 192.168.26.10"

Set-DnsClientServerAddress `
    -InterfaceIndex $InterfaceIndex `
    -ServerAddresses "192.168.26.10"

$DnsServers = @(
    (Get-DnsClientServerAddress `
        -InterfaceIndex $InterfaceIndex `
        -AddressFamily IPv4).ServerAddresses
)

if (
    $DnsServers.Count -ne 1 -or
    $DnsServers[0] -ne "192.168.26.10"
) {
    throw "Interne DNS-server kon niet correct worden ingesteld."
}

Write-Output "Domeincontrollerrecord opvragen via interne DNS..."

$SrvRecords = @(
    Resolve-DnsName `
        -Name "_ldap._tcp.dc._msdcs.$DomainName" `
        -Type SRV `
        -Server "192.168.26.10" `
        -DnsOnly `
        -ErrorAction Stop |
        Where-Object { $_.Type -eq "SRV" }
)

if ($SrvRecords.Count -eq 0) {
    throw "Geen domeincontroller-SRV-record gevonden voor $DomainName."
}

$Computer = Get-CimInstance Win32_ComputerSystem

if ($Computer.PartOfDomain) {
    if ($Computer.Domain -ieq $DomainName) {
        Write-Output "Server2 is al lid van $DomainName."
        exit 0
    }

    throw "Server2 is al lid van een ander domein: $($Computer.Domain)."
}

$SecurePassword = ConvertTo-SecureString `
    $DomainAdminPassword `
    -AsPlainText `
    -Force

$Credential = [System.Management.Automation.PSCredential]::new(
    $DomainAdminUser,
    $SecurePassword
)

Write-Output "Server2 toevoegen aan domein $DomainName..."

$Result = Add-Computer `
    -DomainName $DomainName `
    -OUPath $OUPath `
    -Credential $Credential `
    -PassThru `
    -ErrorAction Stop

if (-not $Result.HasSucceeded) {
    throw "De domeinjoin van server2 is niet geslaagd."
}

Write-Output "Domeinjoin uitgevoerd. Vagrant herstart server2."