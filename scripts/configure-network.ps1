param(
    [Parameter(Mandatory=$true)]
    [string]$IPAddress
)

$adapter = Get-NetAdapter | Where-Object {
    (Get-NetIPConfiguration -InterfaceIndex $_.ifIndex).IPv4DefaultGateway -eq $null
}

if (-not (Get-NetIPAddress -InterfaceAlias $adapter.Name -IPAddress $IPAddress -ErrorAction SilentlyContinue)) {
    New-NetIPAddress -InterfaceAlias $adapter.Name -IPAddress $IPAddress -PrefixLength 24
}