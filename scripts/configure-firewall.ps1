#Requires -RunAsAdministrator

param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('server1', 'server2', 'server3', 'client')]
    [string]$Machine
)

$ErrorActionPreference = 'Stop'

if ($env:COMPUTERNAME -ine $Machine) {
    throw "Verkeerde machine: verwacht $Machine, gevonden $env:COMPUTERNAME."
}

if ($Machine -eq 'client') {
    throw "Dit script configureert alleen de drie servers."
}

$LabSubnet = '192.168.26.0/24'
$NatGateway = '10.0.2.2'

$ServerIPs = @{
    server1 = '192.168.26.10'
    server2 = '192.168.26.20'
    server3 = '192.168.26.30'
}

$LabIP = $ServerIPs[$Machine]

# ------------------------------------------------------------------
# Voorcontroles: nog geen firewallwijzigingen.
# ------------------------------------------------------------------

$LabAddresses = @(
    Get-NetIPAddress -AddressFamily IPv4 |
        Where-Object { $_.IPAddress -eq $LabIP }
)

if ($LabAddresses.Count -ne 1) {
    throw "Verwacht exact een interface met IP $LabIP."
}

$LabInterface = $LabAddresses[0].InterfaceAlias

$NatRoutes = @(
    Get-NetRoute -AddressFamily IPv4 -DestinationPrefix '0.0.0.0/0' |
        Where-Object { $_.NextHop -eq $NatGateway }
)

if ($NatRoutes.Count -ne 1) {
    throw "Verwacht exact een NAT-default-route via $NatGateway."
}

$NatInterface = $NatRoutes[0].InterfaceAlias

$NatIPs = @(
    Get-NetIPAddress `
        -InterfaceIndex $NatRoutes[0].InterfaceIndex `
        -AddressFamily IPv4 |
        Select-Object -ExpandProperty IPAddress
)

$WinRMConnections = @(
    Get-NetTCPConnection -State Established -LocalPort 5985 |
        Where-Object {
            $_.LocalAddress -in $NatIPs
        }
)

if ($WinRMConnections.Count -eq 0) {
    throw "Voer dit script via de Vagrant-firewallprovisioner uit: geen NAT-WinRM-verbinding gevonden."
}

$UnexpectedSources = @(
    $WinRMConnections |
        Where-Object { $_.RemoteAddress -ne $NatGateway }
)

if ($UnexpectedSources.Count -gt 0) {
    throw "Afwijkend NAT-WinRM-bronadres gevonden. Firewall niet gewijzigd."
}

# GPO-regels worden niet stilzwijgend door lokale regels vervangen.
$GpoAllowRules = @(
    Get-NetFirewallRule -PolicyStore ActiveStore |
        Where-Object {
            $_.Enabled -eq 'True' -and
            $_.Direction -eq 'Inbound' -and
            $_.Action -eq 'Allow' -and
            $_.PolicyStoreSourceType -eq 'GroupPolicy'
        }
)

if ($GpoAllowRules.Count -gt 0) {
    $Names = $GpoAllowRules.Name -join ', '
    throw "Er zijn actieve inkomende GPO-Allow-regels. Controleer eerst de GPO: $Names"
}

# Bestaande rolgebonden RPC-regels behouden.
$RoleRuleNames = switch ($Machine) {
    'server1' {
        @(
            'ADDS-RPC-TCP-In'
            'ADDS-RPCEPMAP-TCP-In'
            'DNSSrv-RPC-TCP-In'
            'DNSSrv-RPCEPMAP-TCP-In'
        )
    }

    'server2' {
        @(
            'DNSSrv-RPC-TCP-In'
            'DNSSrv-RPCEPMAP-TCP-In'
        )
    }

    'server3' {
        @(
            'Microsoft-Windows-CertificateServices-CertSvc-DCOM-In'
            'Microsoft-Windows-CertificateServices-CertSvc-RPC-EPMAP-In'
            'Microsoft-Windows-CertificateServices-CertSvc-RPC-NP-In'
            'Microsoft-Windows-CertificateServices-CertSvc-RPC-TCP-In'
            'Microsoft-Windows-DHCP-ClientSvc-RPCSS-TCP-In'
            'Microsoft-Windows-DHCP-ClientSvc-RPC-TCP-In'
            'Microsoft-Windows-DHCP-SMB-TCP-In'
        )
    }
}

foreach ($Name in $RoleRuleNames) {
    Get-NetFirewallRule `
        -PolicyStore PersistentStore `
        -Name $Name `
        -ErrorAction Stop |
        Out-Null
}

Write-Output "Machine: $Machine"
Write-Output "Host-Only: $LabInterface ($LabIP)"
Write-Output "NAT: $NatInterface; beheerbron $NatGateway"

# ------------------------------------------------------------------
# Back-up van de toestand voor deze uitvoering.
# ------------------------------------------------------------------

$BackupFolder = 'C:\ProgramData\WS2\Firewall'
New-Item -Path $BackupFolder -ItemType Directory -Force |
    Out-Null

$Stamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
$BackupPath = Join-Path $BackupFolder "$Machine-$Stamp.wfw"

& netsh advfirewall export $BackupPath

if ($LASTEXITCODE -ne 0) {
    throw "Firewallback-up mislukt. Geen wijzigingen uitgevoerd."
}

Write-Output "Back-up: $BackupPath"

# ------------------------------------------------------------------
# Gewenste lokale regels opbouwen.
# ------------------------------------------------------------------

$DesiredNames = [System.Collections.Generic.HashSet[string]]::new(
    [System.StringComparer]::OrdinalIgnoreCase
)

function Set-LabAllowRule {
    param(
        [string]$Name,
        [string]$Protocol,
        [string[]]$LocalPort,
        [string]$InterfaceAlias,
        [string[]]$RemoteAddress,
        [string]$Service,
        [string]$IcmpType
    )

    $Parameters = @{
        PolicyStore    = 'PersistentStore'
        Name           = $Name
        DisplayName    = $Name
        Group          = 'WS2-Managed-Firewall'
        Direction      = 'Inbound'
        Action         = 'Allow'
        Enabled        = 'True'
        Profile        = 'Any'
        Protocol       = $Protocol
        InterfaceAlias = $InterfaceAlias
        RemoteAddress  = $RemoteAddress
    }

    if ($LocalPort) {
        $Parameters.LocalPort = $LocalPort
    }

    if ($Service) {
        $Parameters.Service = $Service
    }

    if ($IcmpType) {
        $Parameters.IcmpType = $IcmpType
    }

    $Existing = Get-NetFirewallRule `
        -PolicyStore PersistentStore `
        -Name $Name `
        -ErrorAction SilentlyContinue

if ($Existing) {
    # Gebruik Name als enige selectieparameter.
    # DisplayName en Group zijn bij Set-NetFirewallRule
    # eveneens selectieparameters en mogen hier niet mee.
    $UpdateParameters = $Parameters.Clone()

    [void]$UpdateParameters.Remove('DisplayName')
    [void]$UpdateParameters.Remove('Group')

    $UpdateParameters.NewDisplayName = $Name

    Set-NetFirewallRule @UpdateParameters | Out-Null
}
else {
    New-NetFirewallRule @Parameters | Out-Null
}

    [void]$DesiredNames.Add($Name)
    Write-Output "Toegestaan: $Name"
}

try {
    # Vagrantbeheer via NAT, uitsluitend vanaf de NAT-gateway.
    Set-LabAllowRule `
        -Name 'WS2-Managed-WinRM-NAT' `
        -Protocol TCP `
        -LocalPort '5985' `
        -InterfaceAlias $NatInterface `
        -RemoteAddress $NatGateway `
        -Service 'Any'

    Set-LabAllowRule `
        -Name 'WS2-Managed-SSH-NAT' `
        -Protocol TCP `
        -LocalPort '22' `
        -InterfaceAlias $NatInterface `
        -RemoteAddress $NatGateway

    # SSH tussen labmachines, onder andere voor beheer zonder GUI.
    Set-LabAllowRule `
        -Name 'WS2-Managed-SSH-Lab' `
        -Protocol TCP `
        -LocalPort '22' `
        -InterfaceAlias $LabInterface `
        -RemoteAddress $LabSubnet

    # Ping voor labdiagnostiek, alleen intern.
    Set-LabAllowRule `
        -Name 'WS2-Managed-Ping-Lab' `
        -Protocol ICMPv4 `
        -IcmpType '8' `
        -InterfaceAlias $LabInterface `
        -RemoteAddress $LabSubnet

    switch ($Machine) {
        'server1' {
            Set-LabAllowRule `
                -Name 'WS2-Managed-Server1-TCP' `
                -Protocol TCP `
                -LocalPort @(
                    '53', '80', '88', '389',
                    '445', '464', '3268', '9389'
                ) `
                -InterfaceAlias $LabInterface `
                -RemoteAddress $LabSubnet

            Set-LabAllowRule `
                -Name 'WS2-Managed-Server1-UDP' `
                -Protocol UDP `
                -LocalPort @('53', '88', '123', '389', '464') `
                -InterfaceAlias $LabInterface `
                -RemoteAddress $LabSubnet
        }

        'server2' {
            Set-LabAllowRule `
                -Name 'WS2-Managed-Server2-DNS-TCP' `
                -Protocol TCP `
                -LocalPort '53' `
                -InterfaceAlias $LabInterface `
                -RemoteAddress $LabSubnet `
                -Service 'DNS'

            Set-LabAllowRule `
                -Name 'WS2-Managed-Server2-DNS-UDP' `
                -Protocol UDP `
                -LocalPort '53' `
                -InterfaceAlias $LabInterface `
                -RemoteAddress $LabSubnet `
                -Service 'DNS'
        }

                'server3' {
            # Bestaande web-enrollmentfunctie behouden.
            Set-LabAllowRule `
                -Name 'WS2-Managed-Server3-WebEnrollment' `
                -Protocol TCP `
                -LocalPort @('80', '443') `
                -InterfaceAlias $LabInterface `
                -RemoteAddress $LabSubnet


            # DHCP Discover kan van 0.0.0.0 komen:
            # daarom geen subnetfilter, wel interface en service.
            Set-LabAllowRule `
                -Name 'WS2-Managed-Server3-DHCPv4' `
                -Protocol UDP `
                -LocalPort @('67', '68') `
                -InterfaceAlias $LabInterface `
                -RemoteAddress 'Any' `
                -Service 'DHCPServer'


            # Dynamische RPC/DCOM-poorten voor externe CA-toegang.
            # AD CS gebruikt na TCP 135 een dynamische hoge TCP-poort.
            Set-LabAllowRule `
                -Name 'WS2-Managed-Server3-RPC-Dynamic' `
                -Protocol TCP `
                -LocalPort '49152-65535' `
                -InterfaceAlias $LabInterface `
                -RemoteAddress $LabSubnet
        }
    }

    # Rolgebonden RPC-regels behouden met bestaande programmafilters.
    foreach ($Name in $RoleRuleNames) {
        Set-NetFirewallRule `
            -PolicyStore PersistentStore `
            -Name $Name `
            -Enabled True `
            -Profile Any `
            -InterfaceAlias $LabInterface `
            -RemoteAddress $LabSubnet

        [void]$DesiredNames.Add($Name)
        Write-Output "Rolgebonden RPC behouden: $Name"
    }

    # Noodzakelijke basisnetwerkregels behouden.
    # Geen Teredo, IPHTTPS, protocol-41-tunnel of algemene IGMP-regel.
    $CoreRules = @(
        Get-NetFirewallRule -PolicyStore PersistentStore |
            Where-Object {
                $_.Direction -eq 'Inbound' -and
                $_.Action -eq 'Allow' -and
                (
                    $_.Name -eq 'CoreNet-DHCP-In' -or
                    $_.Name -eq 'CoreNet-DHCPV6-In' -or
                    $_.Name -eq 'CoreNet-ICMP4-DUFRAG-In' -or
                    $_.Name -like 'CoreNet-ICMP6-*'
                )
            }
    )

    foreach ($Rule in $CoreRules) {
        # Oorspronkelijke adres- en protocolfilters niet verruimen.
        Enable-NetFirewallRule `
            -PolicyStore PersistentStore `
            -Name $Rule.Name

        [void]$DesiredNames.Add($Rule.Name)
    }

    # Alle overige lokale inkomende Allow-uitzonderingen uitschakelen.
    $OtherAllowRules = @(
        Get-NetFirewallRule -PolicyStore PersistentStore |
            Where-Object {
                $_.Enabled -eq 'True' -and
                $_.Direction -eq 'Inbound' -and
                $_.Action -eq 'Allow' -and
                -not $DesiredNames.Contains($_.Name)
            }
    )

    foreach ($Rule in $OtherAllowRules) {
        Disable-NetFirewallRule `
            -PolicyStore PersistentStore `
            -Name $Rule.Name

        Write-Output "Uitgeschakeld: $($Rule.Name)"
    }

    Set-NetFirewallProfile `
        -Profile Domain,Private,Public `
        -Enabled True `
        -DefaultInboundAction Block `
        -DefaultOutboundAction Allow `
        -AllowInboundRules True

    # Controleer ook de effectieve policy, niet alleen lokale opslag.
    $UnexpectedActiveRules = @(
        Get-NetFirewallRule -PolicyStore ActiveStore |
            Where-Object {
                $_.Enabled -eq 'True' -and
                $_.Direction -eq 'Inbound' -and
                $_.Action -eq 'Allow' -and
                -not $DesiredNames.Contains($_.Name)
            }
    )

    if ($UnexpectedActiveRules.Count -gt 0) {
        $Names = $UnexpectedActiveRules.Name -join ', '
        throw "Onverwachte effectieve Allow-regels: $Names"
    }

    Write-Output "`nControle firewallprofielen:"

    Get-NetFirewallProfile -PolicyStore ActiveStore |
        Select-Object Name, Enabled,
            DefaultInboundAction, DefaultOutboundAction |
        Format-Table -AutoSize |
        Out-String -Width 200 |
        Write-Output

    Write-Output "Controle actieve inkomende Allow-regels:"

    Get-NetFirewallRule -PolicyStore ActiveStore |
        Where-Object {
            $_.Enabled -eq 'True' -and
            $_.Direction -eq 'Inbound' -and
            $_.Action -eq 'Allow'
        } |
        Sort-Object Name |
        Select-Object Name, Enabled, Profile |
        Format-Table -AutoSize |
        Out-String -Width 240 |
        Write-Output

    Write-Output "Rolgebonden firewallconfiguratie voltooid voor $Machine."
}
catch {
    $OriginalError = $_

    Write-Warning "Configuratie mislukt; vorige firewallpolicy herstellen."

    & netsh advfirewall import $BackupPath

    if ($LASTEXITCODE -ne 0) {
        Write-Warning "Automatisch herstel mislukt. Back-up: $BackupPath"
    }

    throw $OriginalError
}