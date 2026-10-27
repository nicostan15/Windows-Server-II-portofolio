#Requires -RunAsAdministrator

$ErrorActionPreference = 'Stop'

$ports = @(
    53,    # DNS
    80,    # IIS HTTP
    88,    # Kerberos
    135,   # RPC endpoint mapper
    389,   # LDAP
    445,   # SMB
    464,   # Kerberos password change
    636,   # LDAPS
    3268,  # Global Catalog
    3269,  # Global Catalog over TLS
    5985   # WinRM HTTP, nodig voor Vagrant provisioning
)

& "$PSScriptRoot\..\configure-firewall.ps1" `
    -AllowedPorts $ports `
    -RoleName "DC-DNS-IIS"