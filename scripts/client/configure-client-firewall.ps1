param()

$ErrorActionPreference = "Stop"

Write-Output "Firewallprofielen inschakelen op de client..."

Set-NetFirewallProfile -Profile Domain, Private, Public `
    -Enabled True `
    -DefaultInboundAction Block `
    -DefaultOutboundAction Allow

Write-Output "Essentiële systeemregels inschakelen..."

# Basisnetwerkverkeer: DHCP, DNS, NDP, router discovery, enz.
Get-NetFirewallRule -Group "Core Networking" -ErrorAction SilentlyContinue |
    Where-Object { $_.Direction -eq "Inbound" } |
    Enable-NetFirewallRule

# WinRM is nodig voor Vagrant-provisioning via de NAT-interface.
Get-NetFirewallRule -DisplayGroup "Windows Remote Management" -ErrorAction SilentlyContinue |
    Where-Object {
        $_.Direction -eq "Inbound" -and
        $_.Action -eq "Allow"
    } |
    Enable-NetFirewallRule

Write-Output "Controle firewallprofielen:"
Get-NetFirewallProfile |
    Select-Object Name, Enabled, DefaultInboundAction, DefaultOutboundAction

Write-Output "Clientfirewall is geconfigureerd."