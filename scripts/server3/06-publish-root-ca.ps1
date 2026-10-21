#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Publiceert het publieke rootcertificaat van de Enterprise Root CA
    in Active Directory, zodat domeinleden de CA automatisch vertrouwen.
#>

param(
    [string]$DomainAdminUser = "WS26-JD\Administrator",
    [string]$DomainAdminPassword = "JouwSterkWachtwoord123!",
    [string]$CACommonName = "WS26-JD-Root-CA"
)

$ErrorActionPreference = "Stop"

$CertificatePath = "C:\LabCertificates\$CACommonName.cer"

if (-not (Test-Path $CertificatePath)) {
    throw "Rootcertificaat ontbreekt: $CertificatePath"
}

$TaskName = "WS2-PublishRootCA"
$LogFile = "C:\ProgramData\WS2-PublishRootCA.log"

$Action = New-ScheduledTaskAction `
    -Execute "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" `
    -Argument "-NoProfile -NonInteractive -ExecutionPolicy Bypass " +
    "-Command `"& { certutil -f -dspublish '$CertificatePath' RootCA } " +
    "*> '$LogFile'`""

$Settings = New-ScheduledTaskSettingsSet `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 5) `
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

try {
    Start-ScheduledTask -TaskName $TaskName -ErrorAction Stop

    $Deadline = (Get-Date).AddMinutes(2)

    do {
        Start-Sleep -Seconds 3

        $TaskState = (
            Get-ScheduledTask -TaskName $TaskName -ErrorAction Stop
        ).State.ToString()
    }
    while (
        $TaskState -in @("Running", "Queued") -and
        (Get-Date) -lt $Deadline
    )

    if (-not (Test-Path $LogFile)) {
        throw "Publicatielog ontbreekt: $LogFile"
    }

    $LogContent = Get-Content $LogFile -Raw

    Write-Output $LogContent

    if ($LogContent -notmatch "dsPublish command completed successfully") {
        throw "Publicatie van het rootcertificaat is mislukt."
    }

    Write-Output "Root-CA-certificaat is gepubliceerd in Active Directory."
}
finally {
    Unregister-ScheduledTask `
        -TaskName $TaskName `
        -Confirm:$false `
        -ErrorAction SilentlyContinue
}