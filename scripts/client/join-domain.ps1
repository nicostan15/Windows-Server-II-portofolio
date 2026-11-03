param(
    [string]$DomainName = "WS26-JD.hogent",
    [string]$DomainAdminUser = "WS26-JD\Administrator",
    [string]$DomainAdminPassword = "JouwSterkWachtwoord123!"
)

$ErrorActionPreference = "Stop"

$CurrentDomain = (Get-WmiObject Win32_ComputerSystem).Domain

if ($CurrentDomain -eq $DomainName) {
    Write-Output "Client is al lid van $DomainName."
    exit 0
}

$SecurePassword = ConvertTo-SecureString $DomainAdminPassword -AsPlainText -Force
$Credential = New-Object System.Management.Automation.PSCredential(
    $DomainAdminUser,
    $SecurePassword
)

Add-Computer `
    -DomainName $DomainName `
    -Credential $Credential `
    -ErrorAction Stop

Write-Output "Domeinjoin uitgevoerd. Vagrant herstart de client."