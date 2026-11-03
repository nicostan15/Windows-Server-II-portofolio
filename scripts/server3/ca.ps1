#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Installeert en configureert de Enterprise Root CA op server3.

.DESCRIPTION
    Controleert het domeinlidmaatschap.
    Installeert indien nodig de CA-rol.
    Configureert de CA als deze nog niet geconfigureerd is.
    Exporteert het publieke rootcertificaat voor de latere GPO.

    Bestaande CA-sleutels en databases worden niet overschreven.
#>

param(
    [string]$DomainName = "WS26-JD.hogent",

    [string]$DomainAdminUser = "WS26-JD\Administrator",

    [string]$DomainAdminPassword,

    [string]$CACommonName = "WS26-JD-Root-CA"
)

$ErrorActionPreference = "Stop"

Import-Module ServerManager

# ------------------------------------------------------------------
# 1. Server en domein controleren.
# ------------------------------------------------------------------

if ($env:COMPUTERNAME -ine "server3") {
    throw "Dit script is bedoeld voor server3, niet voor $env:COMPUTERNAME."
}

$Computer = Get-CimInstance -ClassName Win32_ComputerSystem

if (
    -not $Computer.PartOfDomain -or
    $Computer.Domain -ine $DomainName
) {
    throw "Server3 moet eerst lid zijn van $DomainName en daarna herstart zijn."
}

# ------------------------------------------------------------------
# 2. CA-rol installeren.
# ------------------------------------------------------------------

if (-not (Get-WindowsFeature -Name ADCS-Cert-Authority).Installed) {
    Write-Output "Certification Authority-rol installeren..."

    $Result = Install-WindowsFeature `
        -Name ADCS-Cert-Authority `
        -IncludeManagementTools `
        -ErrorAction Stop

    if (-not $Result.Success) {
        throw "Installatie van de CA-rol is mislukt."
    }

    if ($Result.RestartNeeded -eq "Yes") {
        throw "Herstart server3 en voer deze provisioner daarna opnieuw uit."
    }
}
else {
    Write-Output "Certification Authority-rol is al geinstalleerd."
}

Import-Module ADCSDeployment

# ------------------------------------------------------------------
# 3. Bestaande CA-configuratie controleren.
# ------------------------------------------------------------------

$CARegistryPath =
    "HKLM:\SYSTEM\CurrentControlSet\Services\CertSvc\Configuration"

$ActiveCA = $null

if (Test-Path $CARegistryPath) {
    $ActiveCA = (
        Get-ItemProperty -Path $CARegistryPath -ErrorAction Stop
    ).Active
}

if ($ActiveCA) {
    if ($ActiveCA -ne $CACommonName) {
        throw "Er bestaat al een andere CA: $ActiveCA. Deze wordt niet overschreven."
    }

    $ExistingCA = Get-ItemProperty `
        -Path "$CARegistryPath\$ActiveCA" `
        -ErrorAction Stop

    # CAType 0 = Enterprise Root CA.
    if ($ExistingCA.CAType -ne 0) {
        throw "De bestaande CA is geen Enterprise Root CA. Controleer de configuratie."
    }

    Write-Output "Enterprise Root CA $CACommonName is al geconfigureerd."
}
else {
    if ([string]::IsNullOrWhiteSpace($DomainAdminPassword)) {
        throw "Geen domein-Administratorwachtwoord ontvangen vanuit Vagrant."
    }

    $SecurePassword = ConvertTo-SecureString `
        -String $DomainAdminPassword `
        -AsPlainText `
        -Force

    $Credential = [System.Management.Automation.PSCredential]::new(
        $DomainAdminUser,
        $SecurePassword
    )

    $DistinguishedNameSuffix = (
        $DomainName.Split(".") |
            ForEach-Object { "DC=$_" }
    ) -join ","

    Write-Output "Enterprise Root CA $CACommonName configureren..."

    $CAParameters = @{
        CAType                    = "EnterpriseRootCA"
        CACommonName              = $CACommonName
        CADistinguishedNameSuffix = $DistinguishedNameSuffix
        CryptoProviderName        = "RSA#Microsoft Software Key Storage Provider"
        KeyLength                 = 2048
        HashAlgorithmName         = "SHA256"
        ValidityPeriod            = "Years"
        ValidityPeriodUnits       = 5
        Credential                = $Credential
        Force                     = $true
        ErrorAction               = "Stop"
    }

    $SetupResult = Install-AdcsCertificationAuthority @CAParameters

    $SetupResult |
        Format-List * |
        Out-String -Width 200 |
        Write-Output

    if ($SetupResult.ErrorId -ne 0) {
        throw "CA-configuratie mislukt: $($SetupResult.ErrorString)"
    }
}

# ------------------------------------------------------------------
# 4. CA-service starten en controleren.
# ------------------------------------------------------------------

Start-Service -Name CertSvc -ErrorAction Stop

$Service = Get-Service -Name CertSvc -ErrorAction Stop

if ($Service.Status -ne "Running") {
    throw "De Certification Authority-service draait niet."
}

# ------------------------------------------------------------------
# 5. Publiek CA-certificaat lokaal exporteren.
# ------------------------------------------------------------------

$ExportDirectory = "C:\LabCertificates"
$CertificatePath = Join-Path $ExportDirectory "$CACommonName.cer"

New-Item `
    -Path $ExportDirectory `
    -ItemType Directory `
    -Force |
    Out-Null

Write-Output "Publiek CA-certificaat exporteren..."

$CAConfig = "$env:COMPUTERNAME\$CACommonName"

& certutil.exe -f -config "$CAConfig" "-ca.cert" "$CertificatePath"

if ($LASTEXITCODE -ne 0) {
    throw "Export van het publieke CA-certificaat is mislukt."
}

if (
    -not (Test-Path $CertificatePath) -or
    (Get-Item $CertificatePath).Length -eq 0
) {
    throw "Het geexporteerde CA-certificaat ontbreekt of is leeg."
}

# ------------------------------------------------------------------
# 6. Resultaten tonen.
# ------------------------------------------------------------------

$Certificate =
    [System.Security.Cryptography.X509Certificates.X509Certificate2]::new(
        $CertificatePath
    )

Write-Output "Controle CA-service:"

Get-Service -Name CertSvc |
    Format-List Name, DisplayName, Status |
    Out-String -Width 200 |
    Write-Output

Write-Output "Controle publiek CA-certificaat:"

$Certificate |
    Format-List Subject, Issuer, Thumbprint, NotBefore, NotAfter |
    Out-String -Width 200 |
    Write-Output

Write-Output "Enterprise Root CA-configuratie voltooid."
Write-Output "Publiek rootcertificaat: $CertificatePath"
# ------------------------------------------------------------------
# 7. CA Web Enrollment installeren en configureren.
# ------------------------------------------------------------------

Write-Output "CA Web Enrollment-rol controleren..."

if (-not (Get-WindowsFeature -Name ADCS-Web-Enrollment).Installed) {
    $WebResult = Install-WindowsFeature `
        -Name ADCS-Web-Enrollment `
        -IncludeManagementTools `
        -ErrorAction Stop

    if (-not $WebResult.Success) {
        throw "Installatie van CA Web Enrollment is mislukt."
    }

    if ($WebResult.RestartNeeded -eq "Yes") {
        throw "Herstart server3 en voer deze provisioner daarna opnieuw uit."
    }
}
else {
    Write-Output "CA Web Enrollment-rol is al geinstalleerd."
}

Import-Module ADCSDeployment
Import-Module WebAdministration

$WebEnrollmentApplication = Get-WebApplication `
    -Site "Default Web Site" `
    -ErrorAction Stop |
    Where-Object { $_.Path -ieq "/CertSrv" }

if (-not $WebEnrollmentApplication) {
    Write-Output "CA Web Enrollment configureren..."

    # Geen CAConfig meegeven: de CA is lokaal geinstalleerd.
    $WebSetup = Install-AdcsWebEnrollment `
        -Force `
        -ErrorAction Stop

    $WebSetup |
        Format-List * |
        Out-String -Width 200 |
        Write-Output

    if ($WebSetup.ErrorId -ne 0) {
        throw "Web Enrollment-configuratie mislukt: $($WebSetup.ErrorString)"
    }
}
else {
    Write-Output "CertSrv-webapplicatie bestaat al."
}

# ------------------------------------------------------------------
# 8. IIS starten en webapplicatie controleren.
# ------------------------------------------------------------------

Start-Service -Name W3SVC -ErrorAction Stop

$Website = Get-Website -Name "Default Web Site" -ErrorAction Stop

if ($Website.State -ne "Started") {
    Start-Website -Name "Default Web Site" -ErrorAction Stop
}

$WebEnrollmentApplication = Get-WebApplication `
    -Site "Default Web Site" `
    -ErrorAction Stop |
    Where-Object { $_.Path -ieq "/CertSrv" }

if (-not $WebEnrollmentApplication) {
    throw "Controle mislukt: de CertSrv-webapplicatie ontbreekt."
}

# ------------------------------------------------------------------
# 9. HTTP-toegang beperken tot het interne labnetwerk.
# ------------------------------------------------------------------

$FirewallRuleName = "WS2-Server3-WebEnrollment-HTTP"

$FirewallParameters = @{
    Direction     = "Inbound"
    Action        = "Allow"
    Enabled       = "True"
    Profile       = "Domain"
    Protocol      = "TCP"
    LocalPort     = 80
    LocalAddress  = "192.168.26.30"
    RemoteAddress = "192.168.26.0/24"
}

if (Get-NetFirewallRule -Name $FirewallRuleName -ErrorAction SilentlyContinue) {
    Set-NetFirewallRule `
        -Name $FirewallRuleName `
        @FirewallParameters |
        Out-Null
}
else {
    New-NetFirewallRule `
        -Name $FirewallRuleName `
        -DisplayName "WS2 - Server3 Web Enrollment HTTP intern" `
        @FirewallParameters |
        Out-Null
}

Write-Output "Controle Web Enrollment:"

Get-WebApplication -Site "Default Web Site" |
    Where-Object { $_.Path -ieq "/CertSrv" } |
    Format-List Path, ApplicationPool, PhysicalPath |
    Out-String -Width 200 |
    Write-Output

Write-Output "Web Enrollment-installatie en configuratie voltooid."