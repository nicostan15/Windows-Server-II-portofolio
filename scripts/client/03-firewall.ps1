#Requires -RunAsAdministrator

$ErrorActionPreference = 'Stop'

$ports = @(
    5985   # WinRM HTTP, nodig voor Vagrant provisioning
)

& "$PSScriptRoot\..\configure-firewall.ps1" `
    -AllowedPorts $ports `
    -RoleName "Client"