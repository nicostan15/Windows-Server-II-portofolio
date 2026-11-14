#Requires -RunAsAdministrator

param(
    [string]$DomainName = "WS26-JD.hogent",

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ExpectedCertificatePath
)

$ErrorActionPreference = "Stop"

if (-not (
    Test-Path `
        -LiteralPath $ExpectedCertificatePath `
        -PathType Leaf
)) {
    throw "Referentiecertificaat ontbreekt: $ExpectedCertificatePath"
}

$ResolvedPath = (
    Resolve-Path -LiteralPath $ExpectedCertificatePath
).ProviderPath

$Reference = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($ResolvedPath)

try {
    $SimpleName = $Reference.GetNameInfo(
        [System.Security.Cryptography.X509Certificates.X509NameType]::SimpleName,
        $false
    )

    if (
        $Reference.Subject -ne $Reference.Issuer -or
        $SimpleName -ne "WS26-JD-Root-CA"
    ) {
        throw "Het referentiebestand is niet het verwachte rootcertificaat."
    }

    $Now = Get-Date

    if (
        $Reference.NotBefore -gt $Now -or
        $Reference.NotAfter -le $Now
    ) {
        throw "Het referentiecertificaat is momenteel niet geldig."
    }

    $ExpectedThumbprint = $Reference.Thumbprint.ToUpperInvariant()
}
finally {
    $Reference.Dispose()
}
Write-Output "Machine: $env:COMPUTERNAME"
Write-Output "Uitvoeraccount: $([Security.Principal.WindowsIdentity]::GetCurrent().Name)"

$Computer = Get-CimInstance Win32_ComputerSystem

if (
    -not $Computer.PartOfDomain -or
    $Computer.Domain -ine $DomainName
) {
    throw "De client moet lid zijn van $DomainName en na de domeinjoin herstart zijn."
}

Write-Output "Verwachte Root-CA-thumbprint: $ExpectedThumbprint"
Write-Output "Computerbeleid vernieuwen..."

& gpupdate.exe /target:computer /force /wait:120

if ($LASTEXITCODE -ne 0) {
    throw "Vernieuwen van computerbeleid mislukt. Exitcode: $LASTEXITCODE"
}

$RootPath = "Cert:\LocalMachine\Root\$ExpectedThumbprint"

$PolicyPath = (
    "HKLM:\SOFTWARE\Policies\Microsoft\SystemCertificates" +
    "\Root\Certificates\$ExpectedThumbprint"
)

$Deadline = (Get-Date).AddMinutes(3)
$RootCertificate = $null
$PolicyCertificate = $null

do {
    $RootCertificate = Get-Item `
        -LiteralPath $RootPath `
        -ErrorAction SilentlyContinue

    $PolicyCertificate = Get-ItemProperty `
        -LiteralPath $PolicyPath `
        -Name Blob `
        -ErrorAction SilentlyContinue

    if (
        $RootCertificate -and
        $PolicyCertificate -and
        $PolicyCertificate.Blob.Length -gt 0
    ) {
        break
    }

    Write-Output "Rootcertificaat of beleidsopslag nog niet gereed; opnieuw controleren over 10 seconden."
    Start-Sleep -Seconds 10
}
while ((Get-Date) -lt $Deadline)

if (-not $RootCertificate) {
    throw "Root-CA $ExpectedThumbprint ontbreekt in Trusted Root na beleidsvernieuwing."
}

if (
    -not $PolicyCertificate -or
    $PolicyCertificate.Blob.Length -eq 0
) {
    throw "Root-CA $ExpectedThumbprint ontbreekt in de computerbeleidsopslag of heeft een lege Blob."
}

$Now = Get-Date

if (
    $RootCertificate.NotBefore -gt $Now -or
    $RootCertificate.NotAfter -le $Now
) {
    throw "Het Root-CA-certificaat is momenteel niet geldig."
}

Write-Output "Root-CA aanwezig en geldig:"

$RootCertificate |
    Format-List Subject, Issuer, Thumbprint, NotBefore, NotAfter |
    Out-String -Width 200 |
    Write-Output

Write-Output "Certificaat aanwezig in computerbeleidsopslag."
Write-Output "Er is door dit script geen certificaat geimporteerd."

$IntranetUrl = "http://intranet.$DomainName"

Write-Output "Intranet testen: $IntranetUrl"

$Response = Invoke-WebRequest `
    -Uri $IntranetUrl `
    -UseBasicParsing `
    -TimeoutSec 30 `
    -ErrorAction Stop

if ($Response.StatusCode -ne 200) {
    throw "Onverwachte HTTP-status voor intranet: $($Response.StatusCode)"
}

if ($Response.Content -notmatch "Hello World") {
    throw "Intranet geeft HTTP 200, maar de verwachte Hello World-inhoud ontbreekt."
}

Write-Output "PASS: verwachte Root-CA aanwezig, beleidsopslag aanwezig en certificaat geldig."
Write-Output "PASS: intranet bereikbaar met HTTP 200 en Hello World."