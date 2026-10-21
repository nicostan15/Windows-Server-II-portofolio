#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Installeert de DHCP-serverrol op server3.
.DESCRIPTION
    Controleert of DHCP al geïnstalleerd is.
    Installeert indien nodig de rol en de beheertools.
    Autorisatie, scope en opties worden in een volgende stap toegevoegd.
#>

$ErrorActionPreference = "Stop"

Import-Module ServerManager

if ($env:COMPUTERNAME -ine "server3") {
    throw "Dit script is bedoeld voor server3, niet voor $env:COMPUTERNAME."
}

$Feature = Get-WindowsFeature -Name DHCP

if (-not $Feature.Installed) {
    Write-Output "DHCP-serverrol en beheertools installeren..."

    $Result = Install-WindowsFeature `
        -Name DHCP `
        -IncludeManagementTools `
        -ErrorAction Stop

    if (-not $Result.Success) {
        throw "De installatie van de DHCP-serverrol is mislukt."
    }

    if ($Result.RestartNeeded -eq "Yes") {
        Write-Warning "Een herstart is vereist. Herstart via de deploymentprocedure."
    }
}
else {
    Write-Output "DHCP-serverrol is al geïnstalleerd."
}

Import-Module DhcpServer

if (-not (Get-WindowsFeature -Name DHCP).Installed) {
    throw "Controle mislukt: DHCP-serverrol is niet geïnstalleerd."
}

Write-Output "DHCP-serverrol is succesvol geïnstalleerd."

Get-WindowsFeature -Name DHCP |
    Select-Object Name, InstallState

# ------------------------------------------------------------------
# DHCP-scope en exclusion configureren.
# ------------------------------------------------------------------

$ScopeId        = "192.168.26.0"
$ScopeName      = "WS26-JD - Intern netwerk"
$SubnetMask     = "255.255.255.0"
$StartRange     = "192.168.26.100"
$EndRange       = "192.168.26.200"
$ExclusionStart = "192.168.26.151"
$ExclusionEnd   = "192.168.26.200"

Write-Output "DHCP-service starten..."
Start-Service -Name DHCPServer -ErrorAction Stop

# Alle scopes ophalen voorkomt dat een ontbrekende scope
# als fout moet worden onderdrukt.
$Scope = Get-DhcpServerv4Scope -ErrorAction Stop |
    Where-Object { $_.ScopeId.ToString() -eq $ScopeId }

if (-not $Scope) {
    Write-Output "DHCP-scope $StartRange - $EndRange aanmaken..."

    # Eerst inactief aanmaken; pas na de exclusion activeren.
    Add-DhcpServerv4Scope `
        -Name $ScopeName `
        -StartRange $StartRange `
        -EndRange $EndRange `
        -SubnetMask $SubnetMask `
        -State InActive `
        -ErrorAction Stop
}
else {
    # Bestaande afwijkende configuratie niet stilzwijgend overschrijven.
    if (
        $Scope.StartRange.ToString() -ne $StartRange -or
        $Scope.EndRange.ToString() -ne $EndRange -or
        $Scope.SubnetMask.ToString() -ne $SubnetMask
    ) {
        throw "Scope $ScopeId bestaat met een afwijkend bereik of subnetmasker. Controleer de bestaande configuratie."
    }

    Write-Output "DHCP-scope bestaat al met het juiste bereik."
}

$Exclusions = @(
    Get-DhcpServerv4ExclusionRange `
        -ScopeId $ScopeId `
        -ErrorAction Stop
)

$MatchingExclusion = $Exclusions | Where-Object {
    $_.StartRange.ToString() -eq $ExclusionStart -and
    $_.EndRange.ToString() -eq $ExclusionEnd
}

if (-not $MatchingExclusion) {
    Write-Output "Exclusion $ExclusionStart - $ExclusionEnd toevoegen..."

    Add-DhcpServerv4ExclusionRange `
        -ScopeId $ScopeId `
        -StartRange $ExclusionStart `
        -EndRange $ExclusionEnd `
        -ErrorAction Stop
}
else {
    Write-Output "De vereiste exclusion bestaat al."
}

Write-Output "DHCP-scope activeren..."

Set-DhcpServerv4Scope `
    -ScopeId $ScopeId `
    -State Active `
    -ErrorAction Stop

Write-Output "Controle DHCP-scope:"

Get-DhcpServerv4Scope -ScopeId $ScopeId -ErrorAction Stop |
    Format-List ScopeId, Name, StartRange, EndRange, SubnetMask, State |
    Out-String -Width 200 |
    Write-Output

Write-Output "Controle exclusions:"

Get-DhcpServerv4ExclusionRange -ScopeId $ScopeId -ErrorAction Stop |
    Format-List ScopeId, StartRange, EndRange |
    Out-String -Width 200 |
    Write-Output

Get-DhcpServerv4Scope -ScopeId $ScopeId |
    Select-Object ScopeId, Name, StartRange, EndRange, SubnetMask, State

Write-Output "Controle exclusions:"

Get-DhcpServerv4ExclusionRange -ScopeId $ScopeId |
    Select-Object ScopeId, StartRange, EndRange

# ------------------------------------------------------------------
# DHCP-opties voor het interne Host-Only-netwerk.
# ------------------------------------------------------------------

Write-Output "DHCP-opties instellen: DNS-servers en DNS-domeinnaam..."

Set-DhcpServerv4OptionValue `
    -ScopeId $ScopeId `
    -DnsServer "192.168.26.10", "192.168.26.20" `
    -DnsDomain "WS26-JD.hogent" `
    -ErrorAction Stop

Write-Output "Geen routeroptie instellen: Host-Only is enkel intern."

Write-Output "Controle DHCP-opties:"

Get-DhcpServerv4OptionValue -ScopeId $ScopeId -ErrorAction Stop |
    Format-List OptionId, Name, Value |
    Out-String -Width 200 |
    Write-Output