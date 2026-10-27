#Requires -RunAsAdministrator

$ErrorActionPreference = 'Stop'

$ports = @(
    67,    # DHCP server
    135,   # RPC endpoint mapper
    445,   # SMB
    5985   # WinRM HTTP, nodig voor Vagrant provisioning
)

& "$PSScriptRoot\..\configure-firewall.ps1" `
    -AllowedPorts $ports `
    -RoleName "DHCP"