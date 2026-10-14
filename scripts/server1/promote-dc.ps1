# promote-dc.ps1
# Promoveert deze server tot domeincontroller (nieuw forest/domein)
# Domein: WS26-JD.hogent, Forest/Domain functional level: Windows Server 2025
# LET OP: NoRebootOnCompletion staat op $true - Vagrant (reboot: true) verzorgt de herstart

param(
    [string]$DomainName = "WS26-JD.hogent",
    [string]$DomainNetbiosName = "WS26-JD",
    [string]$SafeModePassword = "JouwSterkWachtwoord123!"
)

$isDC = (Get-WindowsFeature -Name AD-Domain-Services).InstallState -eq "Installed" -and (Get-Service -Name NTDS -ErrorAction SilentlyContinue)

if ($isDC) {
    Write-Output "Server is al gepromoveerd tot domeincontroller. Geen actie nodig."
    exit 0
}

Write-Output "AD-Domain-Services rol installeren..."
Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools

Write-Output "Forest '$DomainName' aanmaken met functional level Windows Server 2025..."
Install-ADDSForest `
    -DomainName $DomainName `
    -DomainNetbiosName $DomainNetbiosName `
    -ForestMode "Win2025" `
    -DomainMode "Win2025" `
    -InstallDns:$true `
    -SafeModeAdministratorPassword (ConvertTo-SecureString $SafeModePassword -AsPlainText -Force) `
    -Force:$true `
    -NoRebootOnCompletion:$true