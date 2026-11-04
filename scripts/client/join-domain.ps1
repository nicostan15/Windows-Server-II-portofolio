#Requires -RunAsAdministrator

param(
    [string]$DomainName = "WS26-JD.hogent",

    [string]$OUPath = "OU=Clients,DC=WS26-JD,DC=hogent",

    [string]$DomainController = "server1.WS26-JD.hogent",

    [string]$DomainAdminUser = "WS26-JD\Administrator",

    [Parameter(Mandatory = $true)]
    [string]$DomainAdminPassword
)

$ErrorActionPreference = "Stop"

$System = Get-CimInstance Win32_ComputerSystem

if ($System.Name -ine "CLIENT") {
    throw "Dit script is uitsluitend bedoeld voor CLIENT."
}

if (
    $System.PartOfDomain -and
    $System.Domain -ine $DomainName
) {
    throw "CLIENT is lid van een ander domein: $($System.Domain). Geen wijzigingen uitgevoerd."
}

$SecurePassword = ConvertTo-SecureString `
    $DomainAdminPassword `
    -AsPlainText `
    -Force

$Credential = [PSCredential]::new(
    $DomainAdminUser,
    $SecurePassword
)

Import-Module ActiveDirectory -ErrorAction Stop

$ADParameters = @{
    Server      = $DomainController
    Credential  = $Credential
    ErrorAction = "Stop"
}

$Domain = Get-ADDomain @ADParameters

if ($Domain.DNSRoot -ine $DomainName) {
    throw "De opgegeven domeincontroller hoort niet bij $DomainName."
}

$TargetOU = Get-ADOrganizationalUnit `
    -Identity $OUPath `
    @ADParameters

if ($System.PartOfDomain) {
    Write-Output "CLIENT is al lid van $DomainName; geen nieuwe join."

    $Computer = Get-ADComputer `
        -Identity $System.Name `
        @ADParameters

    $CurrentParent = (
        $Computer.DistinguishedName -split ",", 2
    )[1]

    if ($CurrentParent -ieq $TargetOU.DistinguishedName) {
        Write-Output "PASS: CLIENT staat al in de juiste OU."
        exit 0
    }

    $DefaultContainer = "CN=Computers,$($Domain.DistinguishedName)"

    if ($CurrentParent -ine $DefaultContainer) {
        throw "CLIENT staat in een onverwachte OU of container: $CurrentParent. Geen automatische verplaatsing uitgevoerd."
    }

    Write-Output "CLIENT verplaatsen vanuit de standaardcontainer."
    Write-Output "Van: $($Computer.DistinguishedName)"
    Write-Output "Naar: $($TargetOU.DistinguishedName)"

    Move-ADObject `
        -Identity $Computer.ObjectGUID `
        -TargetPath $TargetOU.DistinguishedName `
        @ADParameters

    $Updated = Get-ADComputer `
        -Identity $Computer.ObjectGUID `
        @ADParameters

    $UpdatedParent = (
        $Updated.DistinguishedName -split ",", 2
    )[1]

    if ($UpdatedParent -ine $TargetOU.DistinguishedName) {
        throw "De OU-verplaatsing is niet bevestigd."
    }

    Write-Output "PASS: $($Updated.DistinguishedName)"
    exit 0
}

Add-Computer `
    -DomainName $DomainName `
    -Server $DomainController `
    -OUPath $TargetOU.DistinguishedName `
    -Credential $Credential `
    -ErrorAction Stop

Write-Output "Domeinjoin uitgevoerd met doel-OU: $OUPath."
Write-Output "Vagrant herstart de client."