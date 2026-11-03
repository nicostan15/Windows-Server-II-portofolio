#Requires -RunAsAdministrator

param(
    [string]$DomainName = "WS26-JD.hogent",
    [string]$CACommonName = "WS26-JD-Root-CA"
)

$ErrorActionPreference = "Stop"

$Computer = Get-CimInstance Win32_ComputerSystem

if (
    -not $Computer.PartOfDomain -or
    $Computer.Domain -ine $DomainName
) {
    throw "De client moet lid zijn van $DomainName en na de domeinjoin herstart zijn."
}

$CAConfig = "server3.$DomainName\$CACommonName"

$CertificatePath = Join-Path `
    $env:TEMP `
    ("WS2-ExpectedRootCA-" + [guid]::NewGuid().ToString("N") + ".cer")

try {
    Write-Output "Publiek certificaat van de huidige CA ophalen..."

    $CertutilArguments = @(
    '-f'
    '-config'
    $CAConfig
    '-ca.cert'
    $CertificatePath
    )

    & certutil.exe @CertutilArguments

    if ($LASTEXITCODE -ne 0) {
        throw "Ophalen van het CA-certificaat mislukt. Exitcode: $LASTEXITCODE"
    }

    $ExpectedCertificate =
        [System.Security.Cryptography.X509Certificates.X509Certificate2]::new(
            $CertificatePath
        )

    $ExpectedThumbprint = $ExpectedCertificate.Thumbprint

    Write-Output "Verwachte Root-CA-thumbprint: $ExpectedThumbprint"
    Write-Output "Computerbeleid vernieuwen..."

    & gpupdate.exe /target:computer /force /wait:120

    if ($LASTEXITCODE -ne 0) {
        throw "Vernieuwen van computerbeleid mislukt. Exitcode: $LASTEXITCODE"
    }

    $Deadline = (Get-Date).AddMinutes(3)
    $RootCertificate = $null

    do {
        $RootCertificate = Get-Item `
            -Path "Cert:\LocalMachine\Root\$ExpectedThumbprint" `
            -ErrorAction SilentlyContinue

        if ($RootCertificate) {
            break
        }

        Write-Output "Huidige Root-CA nog niet aanwezig; opnieuw controleren over 10 seconden..."
        Start-Sleep -Seconds 10
    }
    while ((Get-Date) -lt $Deadline)

    if (-not $RootCertificate) {
        throw "Huidige Root-CA $ExpectedThumbprint ontbreekt in Trusted Root na beleidsvernieuwing."
    }

    $Now = Get-Date

    if (
        $RootCertificate.NotBefore -gt $Now -or
        $RootCertificate.NotAfter -le $Now
    ) {
        throw "Het Root-CA-certificaat is momenteel niet geldig."
    }

    Write-Output "Root-CA aanwezig:"

    $RootCertificate |
        Format-List Subject, Thumbprint, NotBefore, NotAfter |
        Out-String -Width 200 |
        Write-Output

    $IntranetUrl = "http://intranet.$DomainName"

    Write-Output "Intranet testen: $IntranetUrl"

    $Response = Invoke-WebRequest `
        -Uri $IntranetUrl `
        -UseBasicParsing `
        -TimeoutSec 30

    if ($Response.StatusCode -ne 200) {
        throw "Onverwachte HTTP-status voor intranet: $($Response.StatusCode)"
    }

    Write-Output "Intranet is bereikbaar: HTTP 200."
}
finally {
    Remove-Item `
        -Path $CertificatePath `
        -Force `
        -ErrorAction SilentlyContinue
}