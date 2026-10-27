$ErrorActionPreference = "Stop"

Write-Output "Wachten tot domeinlidmaatschap actief is..."
Start-Sleep -Seconds 15

Write-Output "Group Policy vernieuwen..."
gpupdate /force

$Thumbprint = "226C58F452BB9970BD08435929CCEF1DE44670F7"

$Cert = Get-ChildItem Cert:\LocalMachine\Root |
    Where-Object Thumbprint -eq $Thumbprint

if (-not $Cert) {
    throw "Root-CA-certificaat ontbreekt in Trusted Root op de client."
}

Write-Output "Root-CA aanwezig:"
$Cert | Select-Object Subject, Thumbprint, NotAfter

$Response = Invoke-WebRequest -Uri "http://intranet.WS26-JD.hogent" -UseBasicParsing

if ($Response.StatusCode -ne 200) {
    throw "Intranet is niet bereikbaar."
}

Write-Output "Intranet is bereikbaar: HTTP $($Response.StatusCode)."