#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Maakt een domeinbrede GPO voor vertrouwen in de lab-Root-CA.

.DESCRIPTION
    Haalt het publieke CA-certificaat op van server3.
    Leest de Windows-certificaatblob via een tijdelijke certificaatopslag.
    Configureert deze blob als computerbeleid in een aparte GPO.
    Koppelt de GPO aan de domeinroot.

    Uitvoeren nadat de CA op server3 geconfigureerd is.
#>

param(
    [string]$DomainName = "WS26-JD.hogent",

    [string]$CAConfig = "server3.WS26-JD.hogent\WS26-JD-Root-CA",

    [string]$CACommonName = "WS26-JD-Root-CA",

    [string]$GPOName = "WS26 - Vertrouw Root CA"
)

$ErrorActionPreference = "Stop"

if ($env:COMPUTERNAME -ine "server1") {
    throw "Dit script is bedoeld voor server1."
}

Import-Module ActiveDirectory

$Domain = Get-ADDomain -Identity $DomainName -ErrorAction Stop

# ------------------------------------------------------------------
# 1. Group Policy-beheertools installeren.
# ------------------------------------------------------------------

Import-Module ServerManager

if (-not (Get-WindowsFeature -Name GPMC).Installed) {
    $Result = Install-WindowsFeature `
        -Name GPMC `
        -ErrorAction Stop

    if (-not $Result.Success) {
        throw "Installatie van Group Policy-beheertools is mislukt."
    }
}

Import-Module GroupPolicy

# ------------------------------------------------------------------
# 2. Publiek CA-certificaat ophalen.
# ------------------------------------------------------------------

$CertificateDirectory = "C:\LabCertificates"
$CertificatePath = Join-Path $CertificateDirectory "$CACommonName.cer"

New-Item `
    -Path $CertificateDirectory `
    -ItemType Directory `
    -Force |
    Out-Null

Write-Output "Publiek CA-certificaat ophalen van $CAConfig..."

& certutil.exe -f -config "$CAConfig" "-ca.cert" "$CertificatePath"

if ($LASTEXITCODE -ne 0) {
    throw "CA-certificaat ophalen mislukt. Controleer DNS, de CA-service en RPC/firewalltoegang naar server3."
}

$Certificate =
    [System.Security.Cryptography.X509Certificates.X509Certificate2]::new(
        $CertificatePath
    )

if ($Certificate.GetNameInfo(
    [System.Security.Cryptography.X509Certificates.X509NameType]::SimpleName,
    $false
) -ne $CACommonName) {
    throw "Het opgehaalde certificaat heeft niet de verwachte CA-naam."
}

if ($Certificate.Subject -ne $Certificate.Issuer) {
    throw "Het opgehaalde certificaat is niet het verwachte rootcertificaat."
}

if (
    $Certificate.NotAfter -le (Get-Date) -or
    $Certificate.NotBefore -gt (Get-Date)
) {
    throw "Het opgehaalde CA-certificaat is momenteel niet geldig."
}

$Thumbprint = $Certificate.Thumbprint

Write-Output "Opgehaald rootcertificaat: $Thumbprint"

# ------------------------------------------------------------------
# 3. De Windows-certificaatblob uitlezen.
#    Een .cer-bestand is niet rechtstreeks dezelfde data als Blob.
# ------------------------------------------------------------------

$TemporaryStoreName = "WS2Temp_" + [guid]::NewGuid().ToString("N")

$TemporaryStore =
    [System.Security.Cryptography.X509Certificates.X509Store]::new(
        $TemporaryStoreName,
        [System.Security.Cryptography.X509Certificates.StoreLocation]::LocalMachine
    )

$TemporaryRegistryPath =
    "HKLM:\SOFTWARE\Microsoft\SystemCertificates\$TemporaryStoreName"

try {
    $TemporaryStore.Open(
        [System.Security.Cryptography.X509Certificates.OpenFlags]::ReadWrite
    )

    $TemporaryStore.Add($Certificate)

    $BlobPath = "$TemporaryRegistryPath\Certificates\$Thumbprint"

    [byte[]]$CertificateBlob = (
        Get-ItemProperty -Path $BlobPath -Name Blob -ErrorAction Stop
    ).Blob
}
finally {
    $TemporaryStore.Close()

    if (Test-Path $TemporaryRegistryPath) {
        Remove-Item `
            -Path $TemporaryRegistryPath `
            -Recurse `
            -Force `
            -ErrorAction Stop
    }
}

# ------------------------------------------------------------------
# 4. GPO aanmaken of bestaande GPO gebruiken.
# ------------------------------------------------------------------

$GPO = Get-GPO -All -Domain $DomainName |
    Where-Object { $_.DisplayName -eq $GPOName }

if (-not $GPO) {
    Write-Output "GPO aanmaken: $GPOName"

    $GPO = New-GPO `
        -Name $GPOName `
        -Domain $DomainName `
        -Comment "Vertrouwt de publieke lab-Root-CA op domeincomputers." `
        -ErrorAction Stop
}
else {
    Write-Output "GPO bestaat al: $GPOName"
}

# ------------------------------------------------------------------
# 5. Certificaat als computerbeleid opnemen.
# ------------------------------------------------------------------

$PolicyKey =
    "HKLM\Software\Policies\Microsoft\SystemCertificates\Root\Certificates\$Thumbprint"

Set-GPRegistryValue `
    -Guid $GPO.Id `
    -Domain $DomainName `
    -Key $PolicyKey `
    -ValueName "Blob" `
    -Type Binary `
    -Value $CertificateBlob `
    -ErrorAction Stop |
    Out-Null

# ------------------------------------------------------------------
# 6. GPO aan domeinroot koppelen.
# ------------------------------------------------------------------

$Target = $Domain.DistinguishedName

$ExistingLink = (
    Get-GPInheritance -Target $Target -Domain $DomainName
).GpoLinks | Where-Object {
    $_.GpoId -eq $GPO.Id
}

if (-not $ExistingLink) {
    New-GPLink `
        -Guid $GPO.Id `
        -Domain $DomainName `
        -Target $Target `
        -LinkEnabled Yes `
        -ErrorAction Stop |
        Out-Null
}
else {
    Set-GPLink `
        -Guid $GPO.Id `
        -Domain $DomainName `
        -Target $Target `
        -LinkEnabled Yes `
        -ErrorAction Stop |
        Out-Null
}

# ------------------------------------------------------------------
# 7. Controle.
# ------------------------------------------------------------------

Write-Output "Controle certificaatbeleid:"

Get-GPRegistryValue `
    -Guid $GPO.Id `
    -Domain $DomainName `
    -Key $PolicyKey `
    -ValueName Blob |
    Select-Object KeyPath, ValueName, Type |
    Format-List |
    Out-String -Width 200 |
    Write-Output

Write-Output "GPO aangemaakt/geconfigureerd: $GPOName"
Write-Output "Gekoppeld aan: $Target"
Write-Output "Rootcertificaat: $Thumbprint"
Write-Output "Clienttoepassing moet nog worden gecontroleerd."