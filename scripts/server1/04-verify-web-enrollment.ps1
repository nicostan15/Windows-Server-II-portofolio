# scripts/server1/04-verify-web-enrollment.ps1
# Controleert de Web Enrollment-ingang vanaf server1.

$ErrorActionPreference = "Stop"

$WebFqdn = "server3.WS26-JD.hogent"
$HttpUrl = "http://$WebFqdn/CertSrv/"
$ExpectedDestination = "https://$WebFqdn/certsrv/Default.asp"
$Domain = "WS26-JD"
$AdminUser = "Administrator"

$AdminPassword = $env:WS26_ADMIN_PASSWORD

if ([string]::IsNullOrWhiteSpace($AdminPassword)) {
    throw "Stel eerst de omgevingsvariabele WS26_ADMIN_PASSWORD in."
}

Write-Output "Controle Web Enrollment vanaf server1..."
Write-Output "HTTP-ingang: $HttpUrl"

# 1. HTTP-aanvraag zonder credentials.
#    Automatische redirects uitschakelen zodat we de redirect expliciet controleren.
$Request = [System.Net.HttpWebRequest]::Create($HttpUrl)
$Request.AllowAutoRedirect = $false
$Request.Timeout = 30000

$RedirectResponse = $Request.GetResponse()

try {
    $RedirectStatus = [int]$RedirectResponse.StatusCode
    $RedirectDestination = $RedirectResponse.Headers["Location"]
}
finally {
    $RedirectResponse.Close()
}

if (
    $RedirectStatus -ne 302 -or
    $RedirectDestination -ne $ExpectedDestination
) {
    throw "Onverwachte redirect: HTTP $RedirectStatus naar '$RedirectDestination'."
}

Write-Output "HTTP-redirect: 302 naar $RedirectDestination"

# 2. Gecontroleerde HTTPS-bestemming met domeincredentials ophalen.
$SecurePassword = ConvertTo-SecureString `
    $AdminPassword `
    -AsPlainText `
    -Force

$Credential = [System.Management.Automation.PSCredential]::new(
    "$Domain\$AdminUser",
    $SecurePassword
)

$Page = Invoke-WebRequest `
    -Uri $RedirectDestination `
    -Credential $Credential `
    -UseBasicParsing `
    -TimeoutSec 30 `
    -ErrorAction Stop

if ($Page.StatusCode -ne 200) {
    throw "HTTPS-pagina retourneert HTTP $($Page.StatusCode) in plaats van 200."
}

$Title = [regex]::Match(
    $Page.Content,
    '(?is)<title[^>]*>(.*?)</title>'
).Groups[1].Value.Trim()

if ($Title -notmatch "Certificate Services") {
    throw "De HTTPS-pagina bevat niet de verwachte Certificate Services-titel."
}

Write-Output "HTTPS-pagina: HTTP 200"
Write-Output "Paginatitel: $Title"
Write-Output "Web Enrollment is correct bereikbaar via http://$WebFqdn/CertSrv/."