#Requires -RunAsAdministrator

param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$DomainAdminUser,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$DomainAdminPassword
)

<#
.SYNOPSIS
    Installeert en configureert DHCP op server3.

.DESCRIPTION
    Controleert of DHCP al geinstalleerd is.
    Installeert indien nodig de rol en de beheertools.
    Configureert de scope, exclusion en DHCP-opties.
    Bindt de DHCP-serverdienst uitsluitend aan de interne interface.
    Controleert en configureert AD-autorisatie via een tijdelijke taak
    met expliciete domeincredentials.

    Bestaande afwijkende scopeconfiguratie wordt niet stilzwijgend
    overschreven. Bestaande leases worden niet verwijderd.
#>

$ErrorActionPreference = "Stop"

Import-Module ServerManager -ErrorAction Stop

if ($env:COMPUTERNAME -ine "server3") {
    throw "Dit script is bedoeld voor server3, niet voor $env:COMPUTERNAME."
}

$Feature = Get-WindowsFeature -Name DHCP

if (-not $Feature.Installed) {
    Write-Output "DHCP-serverrol en beheertools installeren..."

    $Result = Install-WindowsFeature `
        -Name DHCP `
        -IncludeManagementTools `
        -ErrorAction Stop

    if (-not $Result.Success) {
        throw "De installatie van de DHCP-serverrol is mislukt."
    }

    if ($Result.RestartNeeded -eq "Yes") {
        Write-Warning "Een herstart is vereist. Herstart via de deploymentprocedure."
    }
}
else {
    Write-Output "DHCP-serverrol is al geinstalleerd."
}

Import-Module DhcpServer -ErrorAction Stop

if (-not (Get-WindowsFeature -Name DHCP).Installed) {
    throw "Controle mislukt: DHCP-serverrol is niet geinstalleerd."
}

Write-Output "DHCP-serverrol is succesvol geinstalleerd."

Get-WindowsFeature -Name DHCP |
    Select-Object Name, InstallState

# ------------------------------------------------------------------
# DHCP-scope en exclusion configureren.
# ------------------------------------------------------------------

$ScopeId        = "192.168.26.0"
$ScopeName      = "WS26-JD - Intern netwerk"
$SubnetMask     = "255.255.255.0"
$StartRange     = "192.168.26.100"
$EndRange       = "192.168.26.200"
$ExclusionStart = "192.168.26.151"
$ExclusionEnd   = "192.168.26.200"

Write-Output "DHCP-service starten..."

Set-Service -Name DHCPServer -StartupType Automatic -ErrorAction Stop
Start-Service -Name DHCPServer -ErrorAction Stop

# Alle scopes ophalen voorkomt dat een ontbrekende scope
# als fout moet worden onderdrukt.
$Scope = Get-DhcpServerv4Scope -ErrorAction Stop |
    Where-Object { $_.ScopeId.ToString() -eq $ScopeId }

if (-not $Scope) {
    Write-Output "DHCP-scope $StartRange - $EndRange aanmaken..."

    # Eerst inactief aanmaken; pas na de exclusion activeren.
    Add-DhcpServerv4Scope `
        -Name $ScopeName `
        -StartRange $StartRange `
        -EndRange $EndRange `
        -SubnetMask $SubnetMask `
        -State InActive `
        -ErrorAction Stop
}
else {
    # Bestaande afwijkende configuratie niet stilzwijgend overschrijven.
    if (
        $Scope.StartRange.ToString() -ne $StartRange -or
        $Scope.EndRange.ToString() -ne $EndRange -or
        $Scope.SubnetMask.ToString() -ne $SubnetMask
    ) {
        throw "Scope $ScopeId bestaat met een afwijkend bereik of subnetmasker. Controleer de bestaande configuratie."
    }

    Write-Output "DHCP-scope bestaat al met het juiste bereik."
}

$Exclusions = @(
    Get-DhcpServerv4ExclusionRange `
        -ScopeId $ScopeId `
        -ErrorAction Stop
)

$MatchingExclusion = $Exclusions | Where-Object {
    $_.StartRange.ToString() -eq $ExclusionStart -and
    $_.EndRange.ToString() -eq $ExclusionEnd
}

if (-not $MatchingExclusion) {
    Write-Output "Exclusion $ExclusionStart - $ExclusionEnd toevoegen..."

    Add-DhcpServerv4ExclusionRange `
        -ScopeId $ScopeId `
        -StartRange $ExclusionStart `
        -EndRange $ExclusionEnd `
        -ErrorAction Stop
}
else {
    Write-Output "De vereiste exclusion bestaat al."
}

Write-Output "DHCP-scope activeren..."

Set-DhcpServerv4Scope `
    -ScopeId $ScopeId `
    -State Active `
    -ErrorAction Stop

Write-Output "Controle DHCP-scope:"

Get-DhcpServerv4Scope -ScopeId $ScopeId -ErrorAction Stop |
    Format-List ScopeId, Name, StartRange, EndRange, SubnetMask, State |
    Out-String -Width 200 |
    Write-Output

Write-Output "Controle exclusions:"

Get-DhcpServerv4ExclusionRange -ScopeId $ScopeId -ErrorAction Stop |
    Format-List ScopeId, StartRange, EndRange |
    Out-String -Width 200 |
    Write-Output

# Bestaande aanvullende controles behouden.
Get-DhcpServerv4Scope -ScopeId $ScopeId |
    Select-Object ScopeId, Name, StartRange, EndRange, SubnetMask, State

Write-Output "Controle exclusions:"

Get-DhcpServerv4ExclusionRange -ScopeId $ScopeId |
    Select-Object ScopeId, StartRange, EndRange

# ------------------------------------------------------------------
# DHCP-opties voor het interne Host-Only-netwerk.
# ------------------------------------------------------------------

Write-Output "DHCP-opties instellen: DNS-servers en DNS-domeinnaam..."

Set-DhcpServerv4OptionValue `
    -ScopeId $ScopeId `
    -DnsServer "192.168.26.10", "192.168.26.20" `
    -DnsDomain "WS26-JD.hogent" `
    -ErrorAction Stop

Write-Output "Geen routeroptie instellen: Host-Only is enkel intern."

Write-Output "Controle DHCP-opties:"

Get-DhcpServerv4OptionValue -ScopeId $ScopeId -ErrorAction Stop |
    Format-List OptionId, Name, Value |
    Out-String -Width 200 |
    Write-Output

# ------------------------------------------------------------------
# DHCP-serverdienst uitsluitend aan de interne IPv4-interface binden.
# ------------------------------------------------------------------

$InternalIP = "192.168.26.30"

$InternalAdapters = @(
    Get-NetIPAddress -AddressFamily IPv4 -ErrorAction Stop |
        Where-Object { $_.IPAddress -eq $InternalIP }
)

if ($InternalAdapters.Count -ne 1) {
    throw "Verwacht exact een interface met IP $InternalIP."
}

$InternalAlias = $InternalAdapters[0].InterfaceAlias

Write-Output "DHCP-server binden aan $InternalAlias ($InternalIP)..."

# Eerst de gewenste binding inschakelen.
Set-DhcpServerv4Binding `
    -InterfaceAlias $InternalAlias `
    -BindingState $true `
    -ErrorAction Stop

# Eventuele overige DHCP-serverbindings uitschakelen.
$OtherBindings = @(
    Get-DhcpServerv4Binding -ErrorAction Stop |
        Where-Object { $_.InterfaceAlias -ne $InternalAlias }
)

foreach ($Binding in $OtherBindings) {
    Set-DhcpServerv4Binding `
        -InterfaceAlias $Binding.InterfaceAlias `
        -BindingState $false `
        -ErrorAction Stop

    Write-Output "DHCP-serverbinding uitgeschakeld: $($Binding.InterfaceAlias)"
}

Write-Output "Controle DHCP-interfacebindings:"

Get-DhcpServerv4Binding -ErrorAction Stop |
    Format-Table InterfaceAlias, IPAddress, BindingState -AutoSize |
    Out-String -Width 200 |
    Write-Output

$VerifiedBinding = @(
    Get-DhcpServerv4Binding -ErrorAction Stop |
        Where-Object {
            $_.InterfaceAlias -eq $InternalAlias -and
            $_.IPAddress.ToString() -eq $InternalIP -and
            $_.BindingState -eq $true
        }
)

if ($VerifiedBinding.Count -ne 1) {
    throw "Controle mislukt: DHCP is niet correct gebonden aan $InternalIP."
}

# ------------------------------------------------------------------
# AD-autorisatie onder expliciete domeincredentials.
#
# De tijdelijke taak gebruikt een wachtwoordaanmelding, zodat de
# controle niet afhankelijk is van de credentials van de WinRM-sessie.
# Het wachtwoord wordt niet in het workerscript geschreven.
# ------------------------------------------------------------------

Import-Module ScheduledTasks -ErrorAction Stop

$TaskName = "WS2-DHCP-Authorize-" + [guid]::NewGuid().ToString("N")
$WorkFolder = Join-Path $env:ProgramData $TaskName
$WorkerPath = Join-Path $WorkFolder "authorize.ps1"
$ResultPath = Join-Path $WorkFolder "result.json"

$TaskRegistered = $false

try {
    New-Item -Path $WorkFolder -ItemType Directory -Force |
        Out-Null

    # Alleen SYSTEM en lokale Administrators krijgen toegang.
    & "$env:SystemRoot\System32\icacls.exe" `
        $WorkFolder `
        /inheritance:r `
        /grant:r `
        "*S-1-5-18:(OI)(CI)F" `
        "*S-1-5-32-544:(OI)(CI)F" |
        Out-Null

    if ($LASTEXITCODE -ne 0) {
        throw "Beveiligen van de tijdelijke werkmap is mislukt."
    }

    # Deze here-string letterlijk behouden:
    # de variabelen erin worden pas door de tijdelijke taak gebruikt.
    $WorkerScript = @'
$ErrorActionPreference = "Stop"

$resultPath = Join-Path $PSScriptRoot "result.json"
$temporaryResultPath = Join-Path $PSScriptRoot "result.tmp"

$exitCode = 0

try {
    Import-Module DhcpServer -ErrorAction Stop

    $dnsName = "server3.WS26-JD.hogent"
    $ipAddress = "192.168.26.30"

    $authorized = @(Get-DhcpServerInDC -ErrorAction Stop)

    $matching = @(
        $authorized | Where-Object {
            $_.DnsName -ieq $dnsName -and
            $_.IPAddress.ToString() -eq $ipAddress
        }
    )

    $conflicting = @(
        $authorized | Where-Object {
            (
                $_.DnsName -ieq $dnsName -and
                $_.IPAddress.ToString() -ne $ipAddress
            ) -or (
                $_.DnsName -ine $dnsName -and
                $_.IPAddress.ToString() -eq $ipAddress
            )
        }
    )

    if ($conflicting.Count -gt 0) {
        throw "Afwijkende DHCP-autorisatie voor deze DNS-naam of dit IP-adres. Controleer de bestaande AD-registratie."
    }

    if ($matching.Count -eq 0) {
        Add-DhcpServerInDC `
            -DnsName $dnsName `
            -IPAddress $ipAddress `
            -ErrorAction Stop

        $message = "DHCP-server toegevoegd aan AD-autorisatie."
    }
    else {
        $message = "DHCP-server is al correct geautoriseerd."
    }

    $verified = @(
        Get-DhcpServerInDC -ErrorAction Stop |
            Where-Object {
                $_.DnsName -ieq $dnsName -and
                $_.IPAddress.ToString() -eq $ipAddress
            }
    )

    if ($verified.Count -eq 0) {
        throw "AD-autorisatie kon na de controle niet worden bevestigd."
    }

    $result = @{
        Success   = $true
        Message   = $message
        DnsName   = $dnsName
        IPAddress = $ipAddress
    }
}
catch {
    $exitCode = 1

    $result = @{
        Success = $false
        Message = $_.Exception.Message
    }
}

# Eerst volledig schrijven, daarna publiceren voor het hoofdscript.
$result |
    ConvertTo-Json |
    Set-Content -Path $temporaryResultPath -Encoding UTF8

Move-Item -Path $temporaryResultPath -Destination $resultPath -Force

exit $exitCode
'@

    Set-Content `
        -Path $WorkerPath `
        -Value $WorkerScript `
        -Encoding UTF8 `
        -ErrorAction Stop

    $Action = New-ScheduledTaskAction `
        -Execute "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" `
        -Argument "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$WorkerPath`""

    $Settings = New-ScheduledTaskSettingsSet `
        -ExecutionTimeLimit (New-TimeSpan -Minutes 2) `
        -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries

    Write-Output "Tijdelijke taak voor DHCP-autorisatie registreren..."

    Register-ScheduledTask `
        -TaskName $TaskName `
        -Action $Action `
        -Settings $Settings `
        -User $DomainAdminUser `
        -Password $DomainAdminPassword `
        -RunLevel Highest `
        -ErrorAction Stop |
        Out-Null

    $TaskRegistered = $true

    Start-ScheduledTask -TaskName $TaskName -ErrorAction Stop

    $Deadline = (Get-Date).AddSeconds(150)

    while (-not (Test-Path $ResultPath)) {
        if ((Get-Date) -ge $Deadline) {
            $TaskInfo = Get-ScheduledTaskInfo `
                -TaskName $TaskName `
                -ErrorAction Stop

            throw "Timeout tijdens DHCP-autorisatie. LastTaskResult: $($TaskInfo.LastTaskResult)."
        }

        Start-Sleep -Seconds 2
    }

    $AuthorizationResult = Get-Content `
        -Path $ResultPath `
        -Raw `
        -ErrorAction Stop |
        ConvertFrom-Json

    if (-not $AuthorizationResult.Success) {
        throw "DHCP-autorisatie mislukt: $($AuthorizationResult.Message)"
    }

    Write-Output $AuthorizationResult.Message
    Write-Output "Geautoriseerde DNS-naam: $($AuthorizationResult.DnsName)"
    Write-Output "Geautoriseerd IP-adres: $($AuthorizationResult.IPAddress)"

    # Laat de taak normaal afsluiten voordat de tijdelijke bestanden
    # en taakregistratie worden verwijderd.
    $FinishDeadline = (Get-Date).AddSeconds(10)

    while (
        (Get-ScheduledTask -TaskName $TaskName -ErrorAction Stop).State -eq "Running" -and
        (Get-Date) -lt $FinishDeadline
    ) {
        Start-Sleep -Seconds 1
    }
}
finally {
    if ($TaskRegistered) {
        Stop-ScheduledTask `
            -TaskName $TaskName `
            -ErrorAction SilentlyContinue

        Unregister-ScheduledTask `
            -TaskName $TaskName `
            -Confirm:$false `
            -ErrorAction SilentlyContinue
    }

    if (Test-Path $WorkFolder) {
        Remove-Item `
            -Path $WorkFolder `
            -Recurse `
            -Force `
            -ErrorAction SilentlyContinue
    }

        Remove-Variable -Name DomainAdminPassword -ErrorAction SilentlyContinue
}

# ------------------------------------------------------------------
# Eindcontrole.
# ------------------------------------------------------------------

Write-Output "Controle DHCP-service:"

Get-Service -Name DHCPServer -ErrorAction Stop |
    Select-Object Name, Status, StartType |
    Format-Table -AutoSize |
    Out-String -Width 200 |
    Write-Output

Write-Output "Controle scopebezetting:"

Get-DhcpServerv4ScopeStatistics -ScopeId $ScopeId -ErrorAction Stop |
    Format-Table ScopeId, Free, InUse, PercentageInUse -AutoSize |
    Out-String -Width 200 |
    Write-Output

Write-Output "DHCP-configuratie, binding en AD-autorisatie voltooid."