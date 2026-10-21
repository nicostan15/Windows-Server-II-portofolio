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
#    Deze regel kan later naar 05-firewall.ps1 worden verplaatst.
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

# ------------------------------------------------------------------
# 10. HTTPS-certificaat voor Web Enrollment aanvragen.
# ------------------------------------------------------------------

Import-Module PKI
Import-Module WebAdministration

$WebFqdn = "server3.$DomainName"
$ServerAuthenticationOid = "1.3.6.1.5.5.7.3.1"

# Een bestaand geschikt certificaat hergebruiken.
$WebCertificate = Get-ChildItem Cert:\LocalMachine\My |
    Where-Object {
        $_.HasPrivateKey -and
        $_.Subject -eq "CN=$WebFqdn" -and
        $_.NotBefore -le (Get-Date) -and
        $_.NotAfter -gt (Get-Date).AddDays(30) -and
        ($_.DnsNameList.Unicode -contains $WebFqdn) -and
        ($_.EnhancedKeyUsageList.ObjectId.Value -contains
            $ServerAuthenticationOid)
    } |
    Sort-Object NotAfter -Descending |
    Select-Object -First 1

if (-not $WebCertificate) {
    if ([string]::IsNullOrWhiteSpace($DomainAdminPassword)) {
        throw "Domeincredentials ontbreken voor de certificaataanvraag."
    }

    Write-Output "Webservercertificaat aanvragen als $DomainAdminUser..."

    $TaskName = "WS2-WebCertificate-" + [guid]::NewGuid().ToString("N")
    $WorkDirectory = Join-Path "C:\ProgramData" $TaskName

    New-Item -Path $WorkDirectory -ItemType Directory -Force |
        Out-Null

    # Alleen SYSTEM en Administrators mogen deze tijdelijke bestanden wijzigen.
    & icacls.exe $WorkDirectory `
        /inheritance:r `
        /grant:r "*S-1-5-18:(OI)(CI)F" "*S-1-5-32-544:(OI)(CI)F" |
        Out-Null

    if ($LASTEXITCODE -ne 0) {
        throw "Beveiligen van de tijdelijke werkmap is mislukt."
    }

    $HelperPath = Join-Path $WorkDirectory "request-certificate.ps1"
    $ResultPath = Join-Path $WorkDirectory "result.json"

    $HelperScript = @'
param(
    [string]$Fqdn,
    [string]$ResultPath
)

$ErrorActionPreference = "Stop"

try {
    Import-Module PKI

    $Enrollment = Get-Certificate `
        -Template "WebServer" `
        -Url "ldap:" `
        -SubjectName "CN=$Fqdn" `
        -DnsName $Fqdn `
        -CertStoreLocation "Cert:\LocalMachine\My" `
        -ErrorAction Stop

    if (
        $Enrollment.Status.ToString() -ne "Issued" -or
        -not $Enrollment.Certificate
    ) {
        throw "Certificaat niet uitgegeven. Status: $($Enrollment.Status)."
    }

    @{
        Success    = $true
        Identity   = [Security.Principal.WindowsIdentity]::GetCurrent().Name
        Thumbprint = $Enrollment.Certificate.Thumbprint
    } |
        ConvertTo-Json |
        Set-Content -Path $ResultPath -Encoding UTF8

    exit 0
}
catch {
    @{
        Success = $false
        Error   = ($_ | Out-String)
    } |
        ConvertTo-Json |
        Set-Content -Path $ResultPath -Encoding UTF8

    exit 1
}
'@

    Set-Content `
        -Path $HelperPath `
        -Value $HelperScript `
        -Encoding UTF8

    $PowerShellPath =
        "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"

    $TaskArguments =
        '-NoProfile -NonInteractive -ExecutionPolicy Bypass ' +
        "-File `"$HelperPath`" " +
        "-Fqdn `"$WebFqdn`" " +
        "-ResultPath `"$ResultPath`""

    $Action = New-ScheduledTaskAction `
        -Execute $PowerShellPath `
        -Argument $TaskArguments

    $Settings = New-ScheduledTaskSettingsSet `
        -ExecutionTimeLimit (New-TimeSpan -Minutes 3) `
        -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries

    $TaskRegistered = $false

    try {
        Register-ScheduledTask `
            -TaskName $TaskName `
            -Action $Action `
            -Settings $Settings `
            -User $DomainAdminUser `
            -Password $DomainAdminPassword `
            -RunLevel Highest `
            -Force `
            -ErrorAction Stop |
            Out-Null

        $TaskRegistered = $true

        Start-ScheduledTask -TaskName $TaskName -ErrorAction Stop

        $Deadline = (Get-Date).AddMinutes(3)

        do {
            Start-Sleep -Seconds 2

            $TaskState = (
                Get-ScheduledTask -TaskName $TaskName -ErrorAction Stop
            ).State.ToString()

            if (
                $TaskState -notin @("Running", "Queued") -and
                (Test-Path $ResultPath)
            ) {
                break
            }

            if ($TaskState -notin @("Running", "Queued")) {
                $TaskInfo = Get-ScheduledTaskInfo -TaskName $TaskName

                if ($TaskInfo.LastTaskResult -ne 0) {
                    throw "De certificaattaak stopte zonder resultaat. Task Scheduler-code: $($TaskInfo.LastTaskResult)."
                }
            }
        }
        while ((Get-Date) -lt $Deadline)

        if (
            $TaskState -in @("Running", "Queued") -or
            -not (Test-Path $ResultPath)
        ) {
            throw "Geen afgerond aanvraagresultaat binnen drie minuten."
        }

        $RequestResult = Get-Content -Path $ResultPath -Raw |
            ConvertFrom-Json

        if (-not $RequestResult.Success) {
            throw "Certificaataanvraag mislukt: $($RequestResult.Error)"
        }

        Write-Output "Aanvraag uitgevoerd als $($RequestResult.Identity)."

        $WebCertificate = Get-Item `
            -Path "Cert:\LocalMachine\My\$($RequestResult.Thumbprint)" `
            -ErrorAction Stop

        Write-Output "Webservercertificaat ontvangen: $($WebCertificate.Thumbprint)"
    }
    finally {
        if ($TaskRegistered) {
            $RemainingTask = Get-ScheduledTask `
                -TaskName $TaskName `
                -ErrorAction SilentlyContinue

            if ($RemainingTask.State -in @("Running", "Queued")) {
                Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 2
            }

            Unregister-ScheduledTask `
                -TaskName $TaskName `
                -Confirm:$false `
                -ErrorAction SilentlyContinue
        }

        Remove-Item `
            -Path $WorkDirectory `
            -Recurse `
            -Force `
            -ErrorAction SilentlyContinue
    }
}
else {
    Write-Output "Bestaand webservercertificaat wordt hergebruikt."
}

# ------------------------------------------------------------------
# 11. HTTPS-binding aanmaken en certificaat koppelen.
# ------------------------------------------------------------------

$HttpsBinding = Get-WebBinding `
    -Name "Default Web Site" `
    -Protocol "https" |
    Where-Object { $_.bindingInformation -eq "*:443:" }

if (-not $HttpsBinding) {
    New-WebBinding `
        -Name "Default Web Site" `
        -Protocol "https" `
        -IPAddress "*" `
        -Port 443 `
        -ErrorAction Stop
}

$HttpsBinding = Get-WebBinding `
    -Name "Default Web Site" `
    -Protocol "https" |
    Where-Object { $_.bindingInformation -eq "*:443:" }

$HttpsBinding.AddSslCertificate(
    $WebCertificate.Thumbprint,
    "My"
)

# De bestaande SSL-verplichting van CertSrv behouden.

# ------------------------------------------------------------------
# 12. HTTPS toestaan vanaf het interne labnetwerk.
# ------------------------------------------------------------------

$HttpsRuleName = "WS2-Server3-WebEnrollment-HTTPS"

$HttpsRuleParameters = @{
    Direction     = "Inbound"
    Action        = "Allow"
    Enabled       = "True"
    Profile       = "Domain"
    Protocol      = "TCP"
    LocalPort     = 443
    LocalAddress  = "192.168.26.30"
    RemoteAddress = "192.168.26.0/24"
}

if (Get-NetFirewallRule -Name $HttpsRuleName -ErrorAction SilentlyContinue) {
    Set-NetFirewallRule `
        -Name $HttpsRuleName `
        @HttpsRuleParameters |
        Out-Null
}
else {
    New-NetFirewallRule `
        -Name $HttpsRuleName `
        -DisplayName "WS2 - Server3 Web Enrollment HTTPS intern" `
        @HttpsRuleParameters |
        Out-Null
}

Write-Output "Controle HTTPS-certificaat:"

$WebCertificate |
    Format-List Subject, Issuer, Thumbprint, HasPrivateKey, NotAfter |
    Out-String -Width 200 |
    Write-Output

Write-Output "Controle HTTPS-binding:"

Get-WebBinding -Name "Default Web Site" -Protocol "https" |
    Format-List protocol, bindingInformation, certificateHash |
    Out-String -Width 200 |
    Write-Output

Write-Output "Web Enrollment-URL: https://$WebFqdn/certsrv/Default.asp"

# ------------------------------------------------------------------
# 13. HTTP-ingang naar beveiligde Web Enrollment-pagina doorverwijzen.
# ------------------------------------------------------------------

Import-Module ServerManager
Import-Module WebAdministration

if (-not (Get-WindowsFeature -Name Web-Http-Redirect).Installed) {
    $RedirectResult = Install-WindowsFeature `
        -Name Web-Http-Redirect `
        -ErrorAction Stop

    if (-not $RedirectResult.Success) {
        throw "Installatie van IIS HTTP Redirect is mislukt."
    }

    if ($RedirectResult.RestartNeeded -eq "Yes") {
        throw "Herstart server3 en voer deze provisioner opnieuw uit."
    }
}

$RedirectSiteName = "WS2-WebEnrollment-HTTP-Redirect"
$RedirectPath = "C:\inetpub\WS2-WebEnrollment-Redirect"
$RedirectBinding = "192.168.26.30:80:$WebFqdn"
$RedirectDestination = "https://$WebFqdn/certsrv/Default.asp"

New-Item `
    -Path $RedirectPath `
    -ItemType Directory `
    -Force |
    Out-Null

$RedirectSite = Get-Website |
    Where-Object { $_.Name -eq $RedirectSiteName }

if (-not $RedirectSite) {
    New-Website `
        -Name $RedirectSiteName `
        -PhysicalPath $RedirectPath `
        -IPAddress "192.168.26.30" `
        -Port 80 `
        -HostHeader $WebFqdn `
        -ErrorAction Stop |
        Out-Null
}
else {
    $ExistingRedirectBinding = Get-WebBinding `
        -Name $RedirectSiteName `
        -Protocol http |
        Where-Object {
            $_.bindingInformation -eq $RedirectBinding
        }

    if (-not $ExistingRedirectBinding) {
        throw "De redirectsite bestaat met een afwijkende binding. Controleer de IIS-configuratie."
    }
}

$RedirectConfiguration = @{
    PSPath   = "MACHINE/WEBROOT/APPHOST"
    Location = $RedirectSiteName
}

# Alleen deze lege redirectsite accepteert HTTP zonder authenticatie.
# Er worden hier geen certificaataanvragen verwerkt.
Set-WebConfigurationProperty `
    @RedirectConfiguration `
    -Filter "system.webServer/security/access" `
    -Name sslFlags `
    -Value "None"

Set-WebConfigurationProperty `
    @RedirectConfiguration `
    -Filter "system.webServer/security/authentication/anonymousAuthentication" `
    -Name enabled `
    -Value $true

Set-WebConfigurationProperty `
    @RedirectConfiguration `
    -Filter "system.webServer/security/authentication/windowsAuthentication" `
    -Name enabled `
    -Value $false

$RedirectSettings = @{
    destination        = $RedirectDestination
    exactDestination   = $true
    httpResponseStatus = "Found"
    enabled            = $true
}

foreach ($Setting in $RedirectSettings.GetEnumerator()) {
    Set-WebConfigurationProperty `
        @RedirectConfiguration `
        -Filter "system.webServer/httpRedirect" `
        -Name $Setting.Key `
        -Value $Setting.Value
}

if (
    (Get-Website -Name $RedirectSiteName).State -ne "Started"
) {
    Start-Website -Name $RedirectSiteName -ErrorAction Stop
}

Write-Output "HTTP-ingang geconfigureerd:"
Write-Output "http://$WebFqdn/CertSrv/"
Write-Output "Redirectbestemming: $RedirectDestination"

Get-WebBinding -Name $RedirectSiteName |
    Format-List protocol, bindingInformation |
    Out-String -Width 200 |
    Write-Output