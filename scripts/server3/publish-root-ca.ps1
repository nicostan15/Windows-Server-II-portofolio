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


# Verwijder een eventueel oud logbestand.
Remove-Item -Path $LogFile -Force -ErrorAction SilentlyContinue


# Gebruik cmd.exe zodat de omleiding eenvoudig en betrouwbaar is.
$TaskArguments = "/c certutil -f -dspublish `"$CertificatePath`" RootCA > `"$LogFile`" 2>&1"


$Action = New-ScheduledTaskAction `
    -Execute "$env:SystemRoot\System32\cmd.exe" `
    -Argument $TaskArguments


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


        $Task = Get-ScheduledTask -TaskName $TaskName -ErrorAction Stop
        $TaskInfo = Get-ScheduledTaskInfo -TaskName $TaskName -ErrorAction Stop


        $TaskState = $Task.State.ToString()
        $LastResult = $TaskInfo.LastTaskResult
    }
    while (
        $TaskState -in @("Running", "Queued") -and
        (Get-Date) -lt $Deadline
    )


    Write-Output "Taakstatus: $TaskState"
    Write-Output "Laatste taakresultaat: $LastResult"


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