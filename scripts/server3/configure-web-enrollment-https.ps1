#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Configureert het HTTPS-certificaat, de HTTPS-binding en de
    HTTP-redirect voor CA Web Enrollment.

.DESCRIPTION
    Uitvoeren nadat de CA beschikbaar is en de WebServer-
    templatepermissies op server1 geconfigureerd zijn.
#>

param(
    [string]$DomainName = "WS26-JD.hogent",

    [string]$DomainAdminUser = "WS26-JD\Administrator",

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$DomainAdminPassword
)

$ErrorActionPreference = "Stop"

if ($env:COMPUTERNAME -ine "server3") {
    throw "Dit script is bedoeld voor server3."
}

Import-Module ServerManager -ErrorAction Stop

if ((Get-Service -Name CertSvc -ErrorAction Stop).Status -ne "Running") {
    throw "De CA-service moet draaien voordat HTTPS wordt geconfigureerd."
}
# ------------------------------------------------------------------
# 10. HTTPS-certificaat voor Web Enrollment aanvragen.
# ------------------------------------------------------------------

Import-Module PKI
Import-Module WebAdministration

$WebFqdn = "server3.$DomainName"
$ServerAuthenticationOid = "1.3.6.1.5.5.7.3.1"

# Een bestaand webservercertificaat hergebruiken indien geschikt.
$WebCertificate = Get-ChildItem Cert:\LocalMachine\My |
    Where-Object {
        $_.HasPrivateKey -and
        $_.Subject -eq "CN=$WebFqdn" -and
        $_.NotAfter -gt (Get-Date).AddDays(30)
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

$OperationFailed = $false

try {
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

# ------------------------------------------------------------------
# 12a. WebServer-certificaatsjabloon publiceren op de CA.
# ------------------------------------------------------------------

Import-Module AdcsAdministration

$TemplateName = "WebServer"

try {
    $PublishedTemplate = Get-CATemplate |
        Where-Object Name -eq $TemplateName


    if (-not $PublishedTemplate) {
        Write-Output "Certificaatsjabloon '$TemplateName' publiceren op de CA..."


        Add-CATemplate `
            -Name $TemplateName `
            -Force `
            -ErrorAction Stop


        Write-Output "Certificaatsjabloon '$TemplateName' gepubliceerd."
    }
    else {
        Write-Output "Certificaatsjabloon '$TemplateName' is al gepubliceerd."
    }
}
catch {
    @{
        Stage    = "WebServerTemplatePublish"
        Identity = [Security.Principal.WindowsIdentity]::GetCurrent().Name
        Error    = ($_ | Out-String)
        Fqdn     = $Fqdn
    } |
        ConvertTo-Json -Depth 5 |
        Set-Content `
            -Path "C:\ProgramData\WS2-WebCertificate-publish-error.json" `
            -Encoding UTF8


    @{
        Success  = $false
        Identity = [Security.Principal.WindowsIdentity]::GetCurrent().Name
        Error    = "Publicatiefout op WebServer-sjabloon: $($_ | Out-String)"
    } |
        ConvertTo-Json -Depth 5 |
        Set-Content -Path $ResultPath -Encoding UTF8


    exit 1
}

$Diagnostics = [ordered]@{}

$Diagnostics.Identity =
    [Security.Principal.WindowsIdentity]::GetCurrent().Name

try {
    $Diagnostics.CaTemplates =
        (certutil -CATemplates 2>&1 | Out-String)

    $Diagnostics.PublishedTemplate =
        (Get-CATemplate |
            Where-Object Name -eq $TemplateName |
            Format-List * |
            Out-String)

    $Diagnostics.CaConfig =
        (certutil -getconfig 2>&1 | Out-String)
}
catch {
    $Diagnostics.DiagnosticError = ($_ | Out-String)
}


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
    $ErrorReport = @{
        Success     = $false
        Identity    = $Diagnostics.Identity
        Error       = ($_ | Out-String)
        Diagnostics = $Diagnostics
    }

    # Permanent diagnoserapport: blijft bestaan na het opkuisen van de werkmap.
    $ErrorReport |
        ConvertTo-Json -Depth 5 |
        Set-Content `
            -Path "C:\ProgramData\WS2-WebCertificate-last-error.json" `
            -Encoding UTF8

    $ErrorReport |
        ConvertTo-Json -Depth 5 |
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

$LogPath = "C:\ProgramData\WS2-WebCertificate-task.log"

    $TaskArguments =
        '-NoProfile -NonInteractive -ExecutionPolicy Bypass ' +
        "-Command `"& { & '$HelperPath' " +
        "-Fqdn '$WebFqdn' " +
        "-ResultPath '$ResultPath' " +
        "} *> '$LogPath'`""

    $Action = New-ScheduledTaskAction `
        -Execute $PowerShellPath `
        -Argument $TaskArguments

    $Settings = New-ScheduledTaskSettingsSet `
        -ExecutionTimeLimit (New-TimeSpan -Minutes 3) `
        -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries

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

$TaskInfo = Get-ScheduledTaskInfo `
    -TaskName $TaskName `
    -ErrorAction Stop

if ($TaskInfo.LastTaskResult -ne 0) {
    throw (
        "De certificaathelper meldt succes, maar de taak eindigde " +
        "met code $($TaskInfo.LastTaskResult)."
    )
}

Write-Output "Aanvraag uitgevoerd als $($RequestResult.Identity)."
        $WebCertificate = Get-Item `
            -Path "Cert:\LocalMachine\My\$($RequestResult.Thumbprint)" `
            -ErrorAction Stop

        Write-Output "Webservercertificaat ontvangen: $($WebCertificate.Thumbprint)"
    }
catch {
    $OperationFailed = $true
    throw
}
finally {
    $CleanupErrors = @()
    $SafeToRemoveWorkDirectory = $false

    try {
        # Enumereren voorkomt dat een ontbrekende taak zelf
        # als zoekfout behandeld moet worden.
        $RemainingTask = Get-ScheduledTask -ErrorAction Stop |
            Where-Object {
                $_.TaskName -eq $TaskName -and
                $_.TaskPath -eq "\"
            }

        if ($null -ne $RemainingTask) {
            if ($RemainingTask.State -in @("Running", "Queued")) {
                Stop-ScheduledTask `
                    -TaskName $TaskName `
                    -TaskPath "\" `
                    -ErrorAction Stop

                $StopDeadline = (Get-Date).AddSeconds(15)

                do {
                    Start-Sleep -Seconds 1

                    $RemainingTask = Get-ScheduledTask `
                        -TaskName $TaskName `
                        -TaskPath "\" `
                        -ErrorAction Stop
                }
                while (
                    $RemainingTask.State -in @("Running", "Queued") -and
                    (Get-Date) -lt $StopDeadline
                )

                if ($RemainingTask.State -in @("Running", "Queued")) {
                    throw "De tijdelijke taak is niet tijdig gestopt."
                }
            }

            Unregister-ScheduledTask `
                -TaskName $TaskName `
                -TaskPath "\" `
                -Confirm:$false `
                -ErrorAction Stop
        }

        $TaskStillExists = @(
            Get-ScheduledTask -ErrorAction Stop |
                Where-Object {
                    $_.TaskName -eq $TaskName -and
                    $_.TaskPath -eq "\"
                }
        )

        if ($TaskStillExists.Count -gt 0) {
            throw "De tijdelijke taakregistratie bestaat nog."
        }

        $SafeToRemoveWorkDirectory = $true
    }
    catch {
        $CleanupErrors += (
            "Taakopruiming voor ${TaskName}: " +
            $_.Exception.Message
        )
    }

    if ($SafeToRemoveWorkDirectory) {
        try {
            if (Test-Path -LiteralPath $WorkDirectory -ErrorAction Stop) {
                Remove-Item `
                    -LiteralPath $WorkDirectory `
                    -Recurse `
                    -Force `
                    -ErrorAction Stop
            }

            if (Test-Path -LiteralPath $WorkDirectory -ErrorAction Stop) {
                throw "De tijdelijke werkmap bestaat nog."
            }
        }
        catch {
            $CleanupErrors += (
                "Werkmapopruiming voor ${WorkDirectory}: " +
                $_.Exception.Message
            )
        }
    }
    else {
        $CleanupErrors += (
            "Werkmap behouden omdat veilige taakopruiming " +
            "niet kon worden bevestigd: $WorkDirectory"
        )
    }

    if ($CleanupErrors.Count -gt 0) {
        $CleanupMessage = $CleanupErrors -join " | "

        if ($OperationFailed) {
            # De oorspronkelijke fout blijft de hoofdreden van falen.
            Write-Warning `
                -Message "Ook opruiming mislukt: $CleanupMessage" `
                -WarningAction Continue
        }
        else {
            throw "Opruiming mislukt: $CleanupMessage"
        }
    }
    else {
        Write-Output (
            "PASS: tijdelijke certificaattaak en werkmap verwijderd."
        )
    }
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