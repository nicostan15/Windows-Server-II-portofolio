#Requires -RunAsAdministrator

param(
    [string]$DomainName = "WS26-JD.hogent",
    [string]$OUPath = "OU=Servers,DC=WS26-JD,DC=hogent",
    [string]$DomainAdminUser = "WS26-JD\Administrator",

    [Parameter(Mandatory = $true)]
    [string]$DomainAdminPassword
)

$ErrorActionPreference = "Stop"

$Computer = Get-CimInstance Win32_ComputerSystem

if ($Computer.PartOfDomain) {
    if ($Computer.Domain -ieq $DomainName) {
        Write-Output "Server2 is al lid van $DomainName."
        exit 0
    }

    throw "Server2 is al lid van een ander domein: $($Computer.Domain)."
}

$InternalAddresses = @(
    Get-NetIPAddress -AddressFamily IPv4 |
        Where-Object { $_.IPAddress -eq "192.168.26.20" }
)

if ($InternalAddresses.Count -ne 1) {
    throw "Verwacht precies een interne interface met IP 192.168.26.20."
}

Set-DnsClientServerAddress `
    -InterfaceIndex $InternalAddresses[0].InterfaceIndex `
    -ServerAddresses "192.168.26.10"

Write-Output "Server2 toevoegen aan domein $DomainName..."

$SecurePassword = ConvertTo-SecureString `
    $DomainAdminPassword `
    -AsPlainText `
    -Force

$Credential = [System.Management.Automation.PSCredential]::new(
    $DomainAdminUser,
    $SecurePassword
)

Add-Computer `
    -DomainName $DomainName `
    -OUPath $OUPath `
    -Credential $Credential `
    -ErrorAction Stop

Write-Output "Domeinjoin uitgevoerd. Vagrant herstart server2."