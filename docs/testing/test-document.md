# Testdocument — Windows Server II — Deel 1

## Documentgegevens

| Gegeven | Waarde |
|---|---|
| Student | Zelf invullen |
| Klasgroep | Zelf invullen |
| Academiejaar | 2026–2027 |
| Domein | WS26-JD.hogent |
| NetBIOS-domeinnaam | WS26-JD |
| Datum volledige test | Zelf invullen |
| Geteste Git-commit | Zelf invullen |
| Resultaat | Nog uit te voeren |

## 1. Doel en afbakening

Dit document beschrijft hoe de vereisten van deel 1 gecontroleerd worden.

Het heeft drie doelen:

1. Voor de opname vaststellen of de volledige omgeving correct werkt.
2. Testresultaten en eventuele beperkingen eerlijk vastleggen.
3. Tijdens de video snel de belangrijkste functionaliteiten demonstreren.

Dit document is uitgebreider dan de uiteindelijke deployment guide.
De limiet van acht pagina's geldt voor de ingediende deployment guide,
niet als doelstelling voor dit interne testdocument.

De afzonderlijke demochecklist op Orion blijft leidend wanneer daarin
aanvullende demonstratiepunten staan.

### 1.1 Resultaatnotatie

Gebruik per test één van deze statussen:

- NIET GETEST: nog geen uitvoering of bewijs.
- PASS: alle genoemde acceptatiecriteria zijn aangetoond.
- FAIL: minstens één acceptatiecriterium is niet gehaald.
- DEELS: een deel is gecontroleerd, maar het volledige bewijs ontbreekt.

Een bestaande werkende omgeving bewijst niet automatisch dat een volledige
nieuwe uitrol zonder manuele tussenkomst werkt.

### 1.2 Veiligheidsafspraken

- Schakel de firewall niet uit om een test te laten slagen.
- Verwijder geen bestaand certificaat om een nieuwe aanvraag te forceren.
- Verwijder geen domein, DHCP-scope, gebruikers of werkende VM voor een demo.
- Voer geen volledige herprovisioning uit als alleen een uitleescontrole nodig is.
- Een volledige nieuwe uitrol gebeurt alleen in een daarvoor voorbereide,
  vervangbare labomgeving.
- Maak vooraf een bruikbare back-up van je project en eventuele VM-toestand.
- Toon geen echte, hergebruikte wachtwoorden in de opname.
- De tijdelijke DNS-test maakt uitsluitend een eigen testrecord en ruimt dat op.
- Noteer manuele herstelacties. Presenteer een herstelde test niet als bewijs
  dat de oorspronkelijke automatische uitrol al volledig geslaagd was.

## 2. Verwachte omgeving

### 2.1 Rollen en adressen

| Machine | Besturingssysteem | Host-Only-adres | Rollen |
|---|---|---|---|
| server1 | Windows Server 2025 Core | 192.168.26.10/24 | AD DS, primaire DNS, IIS |
| server2 | Windows Server 2025 Core | 192.168.26.20/24 | Secundaire DNS, geen DC |
| server3 | Windows Server 2025 Core | 192.168.26.30/24 | Enterprise Root CA, Web Enrollment, DHCP |
| client | Windows 11 Enterprise | DHCP | Domeinlid, RSAT |

Alle machines hebben:

- Eén VirtualBox NAT-interface.
- Eén Host-Only-interface.
- Geen extra netwerkinterfaces voor deze opdracht.

### 2.2 Verwachte DHCP-configuratie

| Onderdeel | Waarde |
|---|---|
| Scope | 192.168.26.0 |
| Subnetmasker | 255.255.255.0 |
| Scopebereik | 192.168.26.100–192.168.26.200 |
| Exclusion | 192.168.26.151–192.168.26.200 |
| Beschikbaar dynamisch bereik | 192.168.26.100–192.168.26.150 |
| DNS-servers | 192.168.26.10 en 192.168.26.20 |
| DNS-domein | WS26-JD.hogent |
| Routeroptie op Host-Only | Niet nodig voor dit ontwerp |

De NAT-interface behoudt haar eigen VirtualBox NAT-configuratie.

### 2.3 Verwachte namen

| Onderdeel | Waarde |
|---|---|
| Forward lookup zone | WS26-JD.hogent |
| Reverse lookup zone | 26.168.192.in-addr.arpa |
| Intranet | http://intranet.WS26-JD.hogent |
| CA-naam | WS26-JD-Root-CA |
| Web Enrollment-ingang | http://server3.WS26-JD.hogent/CertSrv/ |
| HTTPS-bestemming | https://server3.WS26-JD.hogent/certsrv/Default.asp |
| CA-trust-GPO | WS26 - Vertrouw Root CA |

## 3. Uitvoerlocatie en accounts

### 3.1 Host versus VM

Commando's zoals deze voer je op je eigen host uit:

```powershell
vagrant status
vagrant validate
vagrant ssh server1
```

Na `vagrant ssh server1` zit je op server1.

Als je daar een cmd-prompt krijgt, start je PowerShell:

```cmd
powershell
```

Terug naar de host:

```powershell
exit
```

Daarna nogmaals:

```cmd
exit
```

Voer geen `vagrant`-commando's binnen een VM uit.

### 3.2 Beheerdersrechten

Gebruik voor administratieve controles een verhoogde PowerShell-sessie
met de benodigde domein- of lokale beheerdersrechten.

Controleer altijd waar je zit:

```powershell
hostname
whoami
```

Een `Access denied`-melding is geen bewijs dat een dienst ontbreekt.
Controleer eerst de gebruikte identiteit en rechten.

### 3.3 Testbestanden

| Bestand of map | Betekenis |
|---|---|
| `docs/test-document.md` | Dit testplan |
| `docs/test-results.md` | Ingevulde resultaten en beperkingen |
| `docs/status-log.md` | Historiek van problemen en oplossingen |
| `Vagrantfile` | Uitrolvolgorde en provisioners |
| `scripts/` | Configuratiescripts |
| Tijdelijk CNAME-record | Alleen voor DNS-transferdemo |
| Tijdelijk CA-certificaat in `%TEMP%` | Vergelijking met actuele CA; na test verwijderen |

Voor de controles hoef je je bestaande productiescripts niet te herschrijven.

### T02 — PowerShell-syntaxis

Uitvoeren op de host:

```powershell
& {
    $Failures = @()

    foreach ($File in Get-ChildItem .\scripts -Recurse -File -Filter *.ps1) {
        $Tokens = $null
        $ParseErrors = $null

        $Ast = [System.Management.Automation.Language.Parser]::ParseFile(
            $File.FullName,
            [ref]$Tokens,
            [ref]$ParseErrors
        )

        foreach ($Item in $ParseErrors) {
            $Failures += [PSCustomObject]@{
                File = $File.FullName
                Line = $Item.Extent.StartLineNumber
                Error = $Item.Message
            }
        }

        $HereStrings = $Ast.FindAll({
            param($Node)

            $Node -is
                [System.Management.Automation.Language.StringConstantExpressionAst] -and
            $Node.StringConstantType -eq
                [System.Management.Automation.Language.StringConstantType]::SingleQuotedHereString
        }, $true)

        foreach ($HereString in $HereStrings) {
            # Alleen bekende PowerShell-workerstrings controleren.
            $Assignment = $HereString.Parent

            while (
                $null -ne $Assignment -and
                $Assignment -isnot
                    [System.Management.Automation.Language.AssignmentStatementAst]
            ) {
                $Assignment = $Assignment.Parent
            }

            if (
                $null -eq $Assignment -or
                $Assignment.Left.Extent.Text -notin @(
                    '$HelperScript',
                    '$WorkerScript'
                )
            ) {
                continue
            }

            $InnerTokens = $null
            $InnerErrors = $null

            $null = [System.Management.Automation.Language.Parser]::ParseInput(
                $HereString.Value,
                [ref]$InnerTokens,
                [ref]$InnerErrors
            )

            foreach ($Item in $InnerErrors) {
                $Failures += [PSCustomObject]@{
                    File = $File.FullName
                    Line = "Helperregel $($Item.Extent.StartLineNumber)"
                    Error = $Item.Message
                }
            }
        }
    }

    if ($Failures.Count -gt 0) {
        $Failures | Format-Table -Wrap -AutoSize
        throw "PowerShell-syntaxiscontrole mislukt."
    }

    Write-Output "PASS: geen gevonden syntaxisfouten in scripts en herkende workers."
}
```

Acceptatiecriteria:

- Geen parserfouten.
- De controle voert geen configuratiescripts uit.
- Dit resultaat wordt niet voorgesteld als een functionele test.

Status: SUCCESVOL

### T03 — Boxes en VirtualBox

Verwacht:

- `gusztavvargadr/windows-server-2025-standard-core`, versie `2607.0.0`.
- `gusztavvargadr/windows-11-25h2-enterprise`, versie `2607.1.0`.

Controleer VirtualBox en netwerkconfiguratie:

```powershell
& "$env:ProgramFiles\Oracle\VirtualBox\VBoxManage.exe" --version

& "$env:ProgramFiles\Oracle\VirtualBox\VBoxManage.exe" list hostonlyifs

& "$env:ProgramFiles\Oracle\VirtualBox\VBoxManage.exe" list dhcpservers
```

Controleer de adapters van elke VM:

```powershell
& "$env:ProgramFiles\Oracle\VirtualBox\VBoxManage.exe" showvminfo server1 --machinereadable |
    Select-String '^(nic|hostonlyadapter|hostonlynet)[0-9]+='
```

Herhaal voor `server2`, `server3` en `client`.

Acceptatiecriteria:

- Toegestane vastgepinde boxes.
- VirtualBox-versie binnen de toegestane 7.2.x-reeks.
- Per VM één NAT- en één Host-Only-interface.
- Overige virtuele netwerkadapters zijn uitgeschakeld.
- Alle vier VM's gebruiken hetzelfde bedoelde Host-Only-netwerk.
- De VirtualBox-DHCP-server voor dat Host-Only-netwerk is uitgeschakeld.

Let op:

- Schakel niet de DHCP-functionaliteit van de NAT-engine uit.
- Controleer bij meerdere Host-Only-netwerken het netwerk dat deze VM's echt gebruiken.

Status: SUCCESVOL

## 5. Uitrol en bereikbaarheid

### T04 — Volledige uitrol

Deze test is nodig om de uitrolprocedure zelf te bewijzen.

Een `vagrant up` op reeds bestaande, geconfigureerde VM's is geen bewijs van
een volledig nieuwe installatie.

Voer de echte uitroltest alleen uit in een daarvoor voorbereide,
vervangbare labomgeving.

Op de host:

```powershell
vagrant up
```

Als je deployment guide afzonderlijke stappen voorschrijft, test dan exact
die beschreven procedure.

Acceptatiecriteria:

- De beschreven procedure werkt zonder ongedocumenteerde tussenstappen.
- Reboots worden correct afgehandeld.
- Server1 en DNS zijn beschikbaar vóór domeinjoins.
- Server3 is domeinlid voordat CA-configuratie plaatsvindt.
- Templatepermissies zijn gereed vóór de certificaataanvraag.
- CA-vertrouwen wordt pas gecontroleerd nadat CA en GPO beschikbaar zijn.
- Clientjoin vindt plaats nadat DHCP en domein-DNS werken.
- Fouten worden niet verborgen.

Na de uitrol:

```powershell
vagrant status
```

Verwacht: alle vier VM's `running`.

Noteer:

- Totale uitrolduur:
- Aantal noodzakelijke manuele acties:
- Eventuele foutmeldingen:
- Exact gebruikte uitrolcommando's:

Status: NIET GETEST

### T05 — SSH met actieve firewall

Op de host, afzonderlijk:

```powershell
vagrant ssh server1
```

Op server1:

```cmd
hostname
whoami
```

Verlaat de sessie en herhaal voor:

```powershell
vagrant ssh server2
vagrant ssh server3
vagrant ssh client
```

Acceptatiecriteria:

- SSH werkt op alle vier VM's.
- De firewall is daarbij ingeschakeld.
- Geen tijdelijke firewalluitschakeling nodig.

Status: SUCCESVOL

### T06 — OS en Server Core

Op iedere VM:

```powershell
Get-CimInstance Win32_OperatingSystem |
    Select-Object Caption, Version, BuildNumber

Get-ItemProperty `
    "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" |
    Select-Object ProductName, InstallationType
```

Acceptatiecriteria:

- Server1, server2 en server3 gebruiken Windows Server 2025 Core.
- De client gebruikt Windows 11 Enterprise.
- Alleen de client heeft de voorziene desktop-GUI.

Status: NIET GETEST

## 6. Netwerkconfiguratie

### T07 — Statische serveradressen

Op elke server:

```powershell
Get-NetAdapter |
    Select-Object Name, ifIndex, Status, MacAddress

Get-NetIPConfiguration

Get-NetIPAddress -AddressFamily IPv4 |
    Select-Object InterfaceAlias, IPAddress, PrefixLength, PrefixOrigin

Get-NetRoute -AddressFamily IPv4 -DestinationPrefix "0.0.0.0/0" |
    Select-Object InterfaceAlias, NextHop, RouteMetric
```

Acceptatiecriteria:

- Server1 heeft intern `192.168.26.10/24`.
- Server2 heeft intern `192.168.26.20/24`.
- Server3 heeft intern `192.168.26.30/24`.
- Deze adressen zijn via PowerShell ingesteld.
- De NAT-interface behoudt haar eigen configuratie.
- De Host-Only-interface heeft geen ongewenste default gateway.
- De route naar internet loopt via NAT.

Controleer ook de Vagrantfile:

- `auto_config: false` voor de interne serverinterface.
- De echte interne IP-configuratie gebeurt door het netwerkscript.

Status: NIET GETEST

### T08 — DNS-clientinstellingen en registratie

Op iedere server en op de client:

```powershell
Get-DnsClientServerAddress -AddressFamily IPv4 |
    Select-Object InterfaceAlias, ServerAddresses

$ActiveIndexes = @(
    Get-NetAdapter |
        Where-Object Status -eq "Up" |
        Select-Object -ExpandProperty ifIndex
)

Get-DnsClient |
    Where-Object { $_.InterfaceIndex -in $ActiveIndexes } |
    Select-Object InterfaceAlias,
        RegisterThisConnectionsAddress,
        UseSuffixWhenRegistering
```

Acceptatiecriteria:

- Domeinnaamresolutie gebruikt de interne DNS-servers volgens het ontwerp.
- Geen publieke DNS-server als vervanging voor domein-DNS op de interne interface.
- Op de NAT-interface van alle servers is automatische DNS-registratie uitgeschakeld.
- Op beide actieve clientinterfaces is automatische DNS-registratie uitgeschakeld.
- De uiteindelijke DNS-records bevatten geen ongewenste NAT-adressen.

Een uitgeschakelde registratie-instelling verwijdert niet automatisch oude records.
Daarom wordt de inhoud van DNS afzonderlijk gecontroleerd.

Status: NIET GETEST

## 7. Active Directory

### T09 — Domeinlidmaatschap

Voer op alle vier VM's uit:

```powershell
Get-CimInstance Win32_ComputerSystem |
    Select-Object Name, Domain, PartOfDomain, DomainRole
```

op de client:

```powershell
& {
    $ErrorActionPreference = "Stop"

    Write-Output "===== Machine en account ====="
    hostname
    whoami

    $Computer = Get-CimInstance Win32_ComputerSystem

    Write-Output "===== Domeinlidmaatschap ====="

    $Computer |
        Select-Object Name, Domain, PartOfDomain, DomainRole |
        Format-List

    if ($Computer.Name -ine "CLIENT") {
        throw "Voer deze aanvullende T09-controle uit op CLIENT."
    }

    if (
        -not $Computer.PartOfDomain -or
        $Computer.Domain -ine "WS26-JD.hogent"
    ) {
        throw "De client is niet aangesloten bij het verwachte domein."
    }

    if ($Computer.DomainRole -ne 1) {
        throw "Verwacht DomainRole 1: domeinwerkstation."
    }

    Write-Output "===== Secure channel ====="

    $SecureChannel = Test-ComputerSecureChannel `
        -Verbose `
        -ErrorAction Stop

    [PSCustomObject]@{
        Computer      = $Computer.Name
        Domain        = $Computer.Domain
        SecureChannel = $SecureChannel
    } | Format-List

    if (-not $SecureChannel) {
        throw "De secure-channelcontrole is niet geslaagd."
    }

    Write-Output "PASS: CLIENT is domeinwerkstation en de secure channel werkt."
}
```

Acceptatiecriteria:

- Alle vier machines behoren tot `WS26-JD.hogent`.
- `PartOfDomain` is `True`.
- Server1 is domeincontroller.
- Server2 en server3 zijn member servers.
- De client is een domeinwerkstation.

Op server2, server3 en de client aanvullend:

```powershell
Test-ComputerSecureChannel -Verbose
```

Verwacht: `True`.

Gebruik deze aanvullende secure-channeltest niet als DC-test op server1.

Status: SUCCESVOL

### T10 — Forest- en domain-functional level

Op server1:

```powershell
Import-Module ActiveDirectory

Get-ADDomain |
    Select-Object DNSRoot, NetBIOSName, DomainMode

Get-ADForest |
    Select-Object Name, ForestMode

Get-ADDomainController -Filter * |
    Select-Object HostName, IPv4Address, IsGlobalCatalog
```

Acceptatiecriteria:

- Domein `WS26-JD.hogent`.
- Domeinfunctional level Windows Server 2025.
- Forest-functional level Windows Server 2025.
- Alleen server1 staat als domeincontroller geregistreerd.

Status: NIET GETEST

### T11 — OUs en computerobjecten

Op server1:

```powershell
Get-ADOrganizationalUnit -Filter * |
    Select-Object Name, DistinguishedName |
    Sort-Object Name

Get-ADComputer -Filter * |
    Select-Object Name, DistinguishedName |
    Sort-Object Name
```

Acceptatiecriteria:

- Minstens drie eigen OUs.
- In dit project worden onder andere Beheer, Medewerkers, Servers en Clients verwacht.
- Server2 en server3 staan in de bedoelde server-OU.
- De client staat in de bedoelde client-OU.
- Server1 mag in de standaard-OU Domain Controllers staan.

Status: SUCCESVOL

Hieronder staat het volledige vervangende onderdeel. Alle controles zijn via CLI. Wachtwoorden staan niet in de tekst: bij een eventuele reset voer je een nieuw wachtwoord verborgen in.

De wachtwoordreset staat apart als **optionele herstelactie**; voer die niet opnieuw uit wanneer aanmelden al werkt.

### T12 — Vier gebruikers en correcte rollen

#### Doel

Aantonen dat:

- De vier eigen gebruikers bestaan en zijn ingeschakeld.
- De twee beheerders de bedoelde Domain Admin-rol hebben.
- De twee gewone gebruikers geen ongewenste geprivilegieerde groepslidmaatschappen hebben.
- Gebruikers en OUs centraal aanpasbaar zijn in het script.
- Een gewone domeingebruiker via SSH kan aanmelden op CLIENT.
- Die gebruiker vanuit de gewone sessie geen beheerder-uitleesopdracht kan uitvoeren.

De controles wijzigen geen accounts of rechten, behalve de afzonderlijk gemarkeerde optionele wachtwoordherstelactie.

#### 1. Aanmelden op server1 als domeinbeheerder

Uitvoeren op de host, vanuit de projectmap:

```powershell
vagrant ssh-config server1
```

De eerder vastgestelde SSH-hostpoort is `2222`. Gebruik bij een gewijzigde omgeving de actuele poort uit `ssh-config`.

```powershell
ssh -p 2222 -l 'WS26-JD\Administrator' -o PreferredAuthentications=password -o PasswordAuthentication=yes -o PubkeyAuthentication=no 127.0.0.1
```

Voer het domeinbeheerderswachtwoord uitsluitend bij de wachtwoordprompt in.

Start na aanmelden PowerShell:

```cmd
powershell
```

#### 2. Vier gebruikers en beheerdersrollen controleren

Uitvoeren op server1 als domeinbeheerder:

```powershell
& {
    $ErrorActionPreference = "Stop"

    Import-Module ActiveDirectory

    Write-Output "===== Machine en identiteit ====="
    hostname
    whoami

    $Domain = Get-ADDomain

    if ($Domain.DNSRoot -ine "WS26-JD.hogent") {
        throw "Verkeerd domein: $($Domain.DNSRoot)."
    }

    $Names = @(
        "j.doe.adm",
        "a.smit.adm",
        "p.jansen",
        "m.peeters"
    )

    Write-Output "===== Vier eigen gebruikers ====="

    $Users = @(
        foreach ($Name in $Names) {
            Get-ADUser -Identity $Name -Properties Enabled
        }
    )

    $Users |
        Select-Object SamAccountName, Enabled, DistinguishedName |
        Format-List

    if (@($Users | Where-Object { -not $_.Enabled }).Count -gt 0) {
        throw "Minstens één verwachte gebruiker is uitgeschakeld."
    }

    $DomainAdminSID = "$($Domain.DomainSID.Value)-512"

    Write-Output "===== Effectieve leden van Domain Admins ====="

    $AdminMembers = @(
        Get-ADGroupMember `
            -Identity $DomainAdminSID `
            -Recursive
    )

    $AdminMembers |
        Select-Object Name, SamAccountName, ObjectClass |
        Format-Table -AutoSize

    foreach ($Name in @("j.doe.adm", "a.smit.adm")) {
        if ($Name -notin $AdminMembers.SamAccountName) {
            throw "$Name is niet aangetoond als lid van Domain Admins."
        }
    }

    foreach ($Name in @("p.jansen", "m.peeters")) {
        if ($Name -in $AdminMembers.SamAccountName) {
            throw "Ongewenst Domain Admin-lidmaatschap: $Name."
        }
    }

    Write-Output "PASS: vier gebruikers ingeschakeld en Domain Admin-rollen correct."
}
```

Verwacht:

```text
PASS: vier gebruikers ingeschakeld en Domain Admin-rollen correct.
```

Een aanwezige ingebouwde Administrator telt niet mee als één van de vier eigen gebruikers.

#### 3. Groepen van beide gewone gebruikers controleren

Uitvoeren op server1:

```powershell
& {
    $ErrorActionPreference = "Stop"

    Import-Module ActiveDirectory

    foreach ($Name in @("p.jansen", "m.peeters")) {
        Write-Output "===== Autorisatiegroepen van $Name ====="

        Get-ADAccountAuthorizationGroup -Identity $Name |
            Select-Object Name, SID |
            Sort-Object Name |
            Format-Table -AutoSize
    }
}
```

`Get-ADAccountAuthorizationGroup` haalt de beveiligingsgroepen uit de accountautorisatie op. Beoordeel de volledige lijst, niet alleen rechtstreeks toegekende groepslidmaatschappen. [2153]

Acceptatie:

- Geen Domain Admins, Enterprise Admins of Schema Admins.
- Geen Administrators, Account Operators, Server Operators, Backup Operators of andere ongewenste geprivilegieerde groepen.
- Eventuele eigen groepen afzonderlijk beoordelen op hun gedelegeerde rechten.

Deze lijst is geen volledige audit van alle rechtstreeks of via ACLs gedelegeerde rechten. De functionele clienttest hieronder levert aanvullend bewijs voor de geteste sessie.

#### 4. Aanpasbaarheid van het configuratiescript controleren

Uitvoeren op de host in de projectmap, niet binnen een VM:

```powershell
Get-Content -LiteralPath ".\scripts\server1\create-ous-users.ps1"
```

Controleer:

- OU-namen staan centraal in `$OUs`.
- De vier gebruikers staan centraal in `$Users`.
- Per gebruiker zijn naam, rol en doel-OU aanpasbaar.
- Alleen gebruikers met `Role = "DomainAdmin"` worden aan Domain Admins toegevoegd.

Let op:

- Dit is broncodecontrole; voer het script hiervoor niet opnieuw uit.
- Het huidige script corrigeert bestaande gebruikers niet volledig.
- Een bestaande gebruiker met `Role = "DomainUser"` wordt niet automatisch uit eerder toegekende beheerdersgroepen verwijderd.
- Verberg eventuele wachtwoordwaarden vóór screenshots, exports of video-opnamen.

#### 5. Accountstatus vóór de SSH-test uitlezen

Uitvoeren op server1 als domeinbeheerder:

```powershell
& {
    $ErrorActionPreference = "Stop"

    Import-Module ActiveDirectory

    Get-ADUser `
        -Identity "p.jansen" `
        -Properties Enabled, LockedOut, PasswordExpired,
            PasswordLastSet, pwdLastSet, AccountExpirationDate |
        Select-Object SamAccountName,
            Enabled,
            LockedOut,
            PasswordExpired,
            PasswordLastSet,
            AccountExpirationDate,
            @{
                Name = "MustChangePasswordAtNextLogon"
                Expression = { $_.pwdLastSet -eq 0 }
            } |
        Format-List
}
```

Voor de herhaalde SSH-proef verwachten we:

```text
Enabled                       : True
LockedOut                     : False
PasswordExpired               : False
MustChangePasswordAtNextLogon : False
```

Een andere uitkomst eerst onderzoeken. Herhaal niet onbeperkt mislukte wachtwoordpogingen.

#### 6. Optioneel: wachtwoordherstel voor het labaccount

Overslaan wanneer de gebruiker al met zijn huidige wachtwoord kan aanmelden.

Deze stap wijzigt uitsluitend het wachtwoord en de onmiddellijke wachtwoordwijzigingsverplichting van `p.jansen`. Het is geen uitleescontrole en geen onderdeel dat bij iedere test opnieuw moet worden uitgevoerd.

Uitvoeren op server1 als domeinbeheerder:

```powershell
& {
    $ErrorActionPreference = "Stop"

    Import-Module ActiveDirectory

    $Server = "server1.WS26-JD.hogent"

    $Confirmation = Read-Host (
        "Typ RESET p.jansen om het labwachtwoord te resetten"
    )

    if ($Confirmation -cne "RESET p.jansen") {
        throw "Herstelactie geannuleerd; niets gewijzigd."
    }

    $NewPassword = Read-Host `
        "Voer een nieuw wachtwoord in dat aan het domeinbeleid voldoet" `
        -AsSecureString

    Set-ADAccountPassword `
        -Identity "p.jansen" `
        -Server $Server `
        -Reset `
        -NewPassword $NewPassword `
        -ErrorAction Stop

    Set-ADUser `
        -Identity "p.jansen" `
        -Server $Server `
        -ChangePasswordAtLogon $false `
        -ErrorAction Stop

    Write-Output "Wachtwoordherstel uitgevoerd voor p.jansen."
    Write-Output "Groepslidmaatschappen zijn niet gewijzigd."
}
```

Gebruik een uitsluitend voor dit lab bestemd wachtwoord. Neem het niet op in het testdocument of de opname. Deze herstelactie schakelt niet het normale wachtwoordvervalbeleid uit.

Voer na herstel stap 5 opnieuw uit en noteer de wijziging in het resultatenregister.

#### 7. Via SSH aanmelden als gewone domeingebruiker

Verlaat zo nodig de server1-sessie:

```powershell
exit
```

Daarna vanuit de SSH-shell:

```cmd
exit
```

Controleer op de host de actuele clientpoort:

```powershell
vagrant ssh-config client
```

De eerder vastgestelde SSH-hostpoort is `2211`.

```powershell
ssh -p 2211 -l 'WS26-JD\p.jansen' -o PreferredAuthentications=password -o PasswordAuthentication=yes -o PubkeyAuthentication=no 127.0.0.1
```

Voer het huidige wachtwoord alleen bij de wachtwoordprompt in.

Na aanmelden:

```cmd
powershell
```

Controleer:

```powershell
hostname
whoami
whoami /groups
```

Verwacht:

```text
client
ws26-jd\p.jansen
```

Beoordeel ook het sessietoken:

- Geen Administrators- of Domain Admins-groep, ook niet als “deny only”.
- De eerder geteste sessie toonde `BUILTIN\Users` en `Medium Mandatory Level`.

Bij een geweigerde aanmelding blijft dit onderdeel niet geslaagd. Pas niet zomaar SSH-toegangsbeleid of groepsrechten aan om de test te laten slagen.

#### 8. Rechtencontrole zonder configuratiewijziging

Uitvoeren in dezelfde client-PowerShell als `WS26-JD\p.jansen`:

```powershell
whoami
fltmc.exe filters
```

Verwacht:

```text
ws26-jd\p.jansen

Filter listing failed with error: 0x80070005
Access is denied.
```

`fltmc.exe filters` vraagt een filteroverzicht op; gebruik geen `load`, `unload`, `attach` of `detach`. Microsoft beschrijft het uitvoeren van `fltmc` vanuit een verhoogde opdrachtprompt. [2156]

Beoordeling:

- `Access is denied` bij deze opdracht is het gewenste resultaat.
- Een onverwacht succesvol filteroverzicht eerst onderzoeken.
- Een andere fout, zoals “opdracht niet gevonden”, telt niet als bewijs van een rechtenweigering.
- Deze test bewijst de weigering van deze specifieke beheerder-uitleesopdracht, niet dat iedere denkbare beheerdershandeling is getest.

#### Acceptatiecriteria

- Alle vier eigen gebruikers bestaan en zijn ingeschakeld.
- `j.doe.adm` en `a.smit.adm` hebben de bedoelde Domain Admin-rol.
- De autorisatiegroepen van beide gewone gebruikers zijn beoordeeld en bevatten geen ongewenste geprivilegieerde groepslidmaatschappen.
- Gebruikers en OUs zijn centraal aanpasbaar in het configuratiescript.
- SSH-aanmelding op CLIENT als `p.jansen` slaagt.
- De aangemelde identiteit en sessiegroepen zijn vastgelegd.
- `fltmc.exe filters` wordt vanuit die gewone sessie geweigerd wegens ontbrekende rechten.
- Beheer is uitgevoerd met een afzonderlijk beheerdersaccount.
- Eventuele herstelacties zijn afzonderlijk vermeld.

#### Vastgesteld resultaat

Status: SUCCESVOL

Herstelnotitie:

```text
De eerste SSH-aanmeldproef mislukte.
De accountcontrole toonde een verplichte wachtwoordwijziging.

Voor p.jansen is een nieuw labwachtwoord ingesteld en de
onmiddellijke wijzigingsverplichting uitgeschakeld.
Groepslidmaatschappen zijn niet gewijzigd.

Daarna zijn de SSH-aanmelding en de rechtencontrole geslaagd.
```

## 8. DNS

### T13 — Rollen en zonetypes

Op server1:

```powershell
Get-WindowsFeature -Name AD-Domain-Services, DNS |
    Select-Object Name, InstallState

Get-Service -Name DNS, NTDS |
    Select-Object Name, Status

Get-DnsServerZone |
    Select-Object ZoneName, ZoneType, IsDsIntegrated
```

Op server2:

```powershell
Get-WindowsFeature -Name AD-Domain-Services, DNS |
    Select-Object Name, InstallState

Get-Service -Name DNS |
    Select-Object Name, Status

Get-DnsServerZone |
    Select-Object ZoneName, ZoneType, IsDsIntegrated, MasterServers
```

Acceptatiecriteria:

- Server1 is primaire DNS-server.
- De primaire AD-zones mogen AD-geïntegreerd zijn.
- Server2 heeft de vereiste zones als `Secondary`.
- Server2 gebruikt server1 als master.
- Server2 is geen domeincontroller.
- Forward en reverse lookup zone bestaan op beide DNS-servers.
- Controleer ook de `_msdcs`-zone wanneer die in jouw configuratie
  afzonderlijk wordt gehost.

Status: NIET GETEST

### T14 — Exact één A- en PTR-record per server

```powershell
ssh -p 2222 `
    -l 'WS26-JD\Administrator' `
    -o PreferredAuthentications=password `
    -o PasswordAuthentication=yes `
    -o PubkeyAuthentication=no `
    127.0.0.1
```

Uitvoeren op server1 met DNS-beheerrechten:

```powershell
& {
    $ErrorActionPreference = "Stop"

    $Expected = @(
        @{ Name = "server1"; IP = "192.168.26.10"; PTR = "10" }
        @{ Name = "server2"; IP = "192.168.26.20"; PTR = "20" }
        @{ Name = "server3"; IP = "192.168.26.30"; PTR = "30" }
    )

    foreach ($DnsServer in @("server1", "server2")) {
        Write-Output "===== DNS-server: $DnsServer ====="

        $ARecords = @(
            Get-DnsServerResourceRecord `
                -ComputerName $DnsServer `
                -ZoneName "WS26-JD.hogent" `
                -RRType A `
                -ErrorAction Stop
        )

        $PtrRecords = @(
            Get-DnsServerResourceRecord `
                -ComputerName $DnsServer `
                -ZoneName "26.168.192.in-addr.arpa" `
                -RRType PTR `
                -ErrorAction Stop
        )

        foreach ($Item in $Expected) {
            $A = @(
                $ARecords |
                    Where-Object HostName -eq $Item.Name
            )

            $Ptr = @(
                $PtrRecords |
                    Where-Object HostName -eq $Item.PTR
            )

            if (
                $A.Count -ne 1 -or
                $A.RecordData.IPv4Address.ToString() -ne $Item.IP
            ) {
                throw "Afwijkend A-record voor $($Item.Name) op $DnsServer."
            }

            if (
                $Ptr.Count -ne 1 -or
                $Ptr.RecordData.PtrDomainName.TrimEnd(".") -ine
                    "$($Item.Name).WS26-JD.hogent"
            ) {
                throw "Afwijkend PTR-record voor $($Item.Name) op $DnsServer."
            }

            Write-Output "PASS: $($Item.Name), A en PTR correct."
        }
    }
}
```

De test controleert de naam `server1`, `server2` en `server3`.
Andere noodzakelijke records, zoals het zone-apexrecord of SRV-records,
worden niet als dubbele hostrecords geteld.

Status: NIET GETEST

### T15 — Twee DNS-servers zichtbaar in de zones

Op server1:

```powershell
foreach ($DnsServer in @("server1", "server2")) {
    foreach ($Zone in @(
        "WS26-JD.hogent",
        "26.168.192.in-addr.arpa"
    )) {
        Write-Output "===== $DnsServer / $Zone ====="

        Get-DnsServerResourceRecord `
            -ComputerName $DnsServer `
            -ZoneName $Zone `
            -RRType NS |
            Select-Object HostName,
                @{Name = "NameServer"; Expression = {
                    $_.RecordData.NameServer
                }}
    }
}
```

Acceptatiecriteria:

- De bedoelde zones verwijzen naar beide DNS-servers.
- De nameservernamen kunnen naar de juiste interne adressen worden vertaald.

Status: NIET GETEST

### T16 — Geen NAT-records en geen clientregistratie

Op server1:

```powershell
foreach ($DnsServer in @("server1", "server2")) {
    Write-Output "===== A-records op $DnsServer ====="

    Get-DnsServerResourceRecord `
        -ComputerName $DnsServer `
        -ZoneName "WS26-JD.hogent" `
        -RRType A |
        Select-Object HostName,
            @{Name = "IPv4"; Expression = {
                $_.RecordData.IPv4Address.ToString()
            }}

    Write-Output "===== PTR-records op $DnsServer ====="

    Get-DnsServerResourceRecord `
        -ComputerName $DnsServer `
        -ZoneName "26.168.192.in-addr.arpa" `
        -RRType PTR |
        Select-Object HostName,
            @{Name = "Target"; Expression = {
                $_.RecordData.PtrDomainName
            }}
}
```

Acceptatiecriteria:

- Geen A-records met de NAT-adressen van de servers.
- Geen A-record voor de client door automatische registratie.
- Geen PTR-record voor de client door client- of DHCP-registratie.

Controleer zo nodig ook andere door dit lab beheerde forward zones
op oude NAT-records.

Status: NIET GETEST

### T17 — Automatische zone transfer met tijdelijk CNAME-record

Doel:

- Een wijziging aanmaken op de primaire DNS-server.
- Aantonen dat deze zonder geforceerde handmatige transfer op server2 verschijnt.
- Het testrecord verwijderen en ook die verwijdering op server2 bevestigen.

Uitvoeren op server1.

Deze test wijzigt uitsluitend een eigen tijdelijk CNAME-record.
Laat de PowerShell-sessie open totdat het blok klaar is.

```powershell
& {
    $ErrorActionPreference = "Stop"

    $Zone = "WS26-JD.hogent"
    $Name = "ws2-demo-transfer"
    $Target = "server1.WS26-JD.hogent."
    $Created = $false

    foreach ($DnsServer in @("server1", "server2")) {
        $Existing = @(
            Get-DnsServerResourceRecord `
                -ComputerName $DnsServer `
                -ZoneName $Zone `
                -ErrorAction Stop |
                Where-Object HostName -eq $Name
        )

        if ($Existing.Count -gt 0) {
            throw "Testnaam bestaat al op $DnsServer. Niet overschrijven."
        }
    }

    try {
        Add-DnsServerResourceRecordCName `
            -ComputerName server1 `
            -ZoneName $Zone `
            -Name $Name `
            -HostNameAlias $Target `
            -ErrorAction Stop

        $Created = $true
        $Deadline = (Get-Date).AddSeconds(90)
        $Replicated = @()

        do {
            $Replicated = @(
                Get-DnsServerResourceRecord `
                    -ComputerName server2 `
                    -ZoneName $Zone `
                    -ErrorAction Stop |
                    Where-Object {
                        $_.HostName -eq $Name -and
                        $_.RecordType -eq "CNAME"
                    }
            )

            if ($Replicated.Count -eq 1) {
                break
            }

            Start-Sleep -Seconds 2
        }
        while ((Get-Date) -lt $Deadline)

        if (
            $Replicated.Count -ne 1 -or
            $Replicated.RecordData.HostNameAlias.TrimEnd(".") -ine
                $Target.TrimEnd(".")
        ) {
            throw "Automatische overname niet binnen 90 seconden bevestigd."
        }

        Write-Output "PASS: CNAME automatisch zichtbaar op server2."

        Resolve-DnsName `
            -Name "$Name.$Zone" `
            -Type CNAME `
            -Server "192.168.26.20" `
            -DnsOnly `
            -ErrorAction Stop
    }
    finally {
        if ($Created) {
            Remove-DnsServerResourceRecord `
                -ComputerName server1 `
                -ZoneName $Zone `
                -Name $Name `
                -RRType CNAME `
                -Force `
                -ErrorAction Stop
        }
    }

    $Deadline = (Get-Date).AddSeconds(90)

    do {
        $Remaining = @(
            Get-DnsServerResourceRecord `
                -ComputerName server2 `
                -ZoneName $Zone `
                -ErrorAction Stop |
                Where-Object HostName -eq $Name
        )

        if ($Remaining.Count -eq 0) {
            break
        }

        Start-Sleep -Seconds 2
    }
    while ((Get-Date) -lt $Deadline)

    if ($Remaining.Count -gt 0) {
        throw "Verwijdering nog niet overgenomen op server2."
    }

    Write-Output "PASS: verwijdering automatisch overgenomen op server2."
}
```

Acceptatiecriteria:

- Aanmaak verschijnt automatisch op server2.
- Correct doeladres.
- Verwijdering verschijnt automatisch op server2.
- Geen handmatige zone transfer nodig.

Als de test faalt:

- Noteer de fout.
- Controleer zone-transferrechten, notify-instellingen en firewall.
- Een handmatig geforceerde transfer mag als diagnose,
  maar vervangt dit bewijs van automatische overname niet.
- Bij een fout tijdens de toevoegingscontrole wordt opruiming op server1 geprobeerd;
  controleer daarna ook afzonderlijk of het record op server2 verdwenen is.

Status: NIET GETEST

## 9. DHCP

### T18 — Rol, service, scope en exclusion

#### Aanmelden voor de AD-autorisatiecontrole

Voor `Get-DhcpServerInDC` gebruiken we in deze omgeving
`WS26-JD\Administrator`. Onder het lokale account `server3\vagrant`
mislukte deze controle; onder het domeinaccount werkte ze wel.

Als je nog in de lokale PowerShell-sessie op server3 zit, keer je eerst
terug naar de host:

```powershell
exit
```

Daarna nogmaals vanuit de SSH-shell:

```cmd
exit
```

Voer vervolgens op je host, vanuit de projectmap, uit:

```powershell
ssh -p 2207 `
    -l 'WS26-JD\Administrator' `
    -o PreferredAuthentications=password `
    -o PasswordAuthentication=yes `
    -o PubkeyAuthentication=no `
    127.0.0.1
```

Geef het domein-Administratorwachtwoord op wanneer daarom gevraagd wordt.

Start na aanmelden PowerShell:

```cmd
powershell
```

Controleer de machine en identiteit:

```powershell
hostname
whoami
```

Verwacht:

```text
server3
ws26-jd\administrator
```

Voer daarna de onderstaande T18-commando’s uit.

Let op: `2207` is de momenteel vastgestelde SSH-hostpoort van server3.
Controleer bij een gewijzigde poort of nieuwe uitrol vanaf de host:

```powershell
vagrant ssh-config server3
```

Gebruik dan de poort achter `Port`.

Op server3:

```powershell
Import-Module DhcpServer

Get-WindowsFeature -Name DHCP |
    Select-Object Name, InstallState

Get-Service DHCPServer |
    Select-Object Name, Status, StartType

Get-DhcpServerv4Scope |
    Select-Object ScopeId, Name, State, SubnetMask, StartRange, EndRange

Get-DhcpServerv4ExclusionRange -ScopeId 192.168.26.0

Get-DhcpServerInDC
```

Acceptatiecriteria:

- DHCP-rol geïnstalleerd.
- DHCPServer-service draait.
- Scope actief.
- Scopebereik `.100` tot en met `.200`.
- Exclusion `.151` tot en met `.200`.
- Server3 is geautoriseerd met DNS-naam en IP `192.168.26.30`.

Status: SUCCESVOL

### T19 — Opties, bindings en DNS-registratiebeleid

Op server3:

```powershell
Get-DhcpServerv4OptionValue -ScopeId 192.168.26.0 |
    Select-Object OptionId, Name, Value

Get-DhcpServerv4OptionValue |
    Select-Object OptionId, Name, Value

Get-DhcpServerv4Binding |
    Select-Object InterfaceAlias, IPAddress, BindingState

Get-DhcpServerv4DnsSetting

Get-DhcpServerv4DnsSetting -ScopeId 192.168.26.0
```

Acceptatiecriteria:

- Optie 6 bevat beide interne DNS-servers.
- Optie 15 bevat `WS26-JD.hogent`.
- Geen ongewenste routeroptie via scope- of serverinstellingen.
- DHCP-server is alleen aan de bedoelde interne interface gebonden.
- DHCP registreert geen ongewenste clientrecords in DNS.
- In dit project wordt `DynamicUpdates = Never` verwacht.

Status: NIET GETEST

### T20 — Echte clientlease

#### Doel en uitvoering

Aantonen dat de interne clientinterface een geldig DHCP-adres ontvangt van server3 en dat op server3 de bijbehorende actieve lease bestaat.

De controle bestaat uit twee delen:

1. Op CLIENT: DHCP-server, IPv4-adres, subnetmasker, DNS-servers en MAC-adres uitlezen.
2. Op server3: de actieve lease vergelijken met het adres en de MAC van de client.

Alle onderstaande opdrachten zijn uitleescontroles. Er worden geen adressen gewijzigd, leases vrijgegeven of rechten aangepast.

Gebruik uitsluitend CLI. Voer `vagrant`- en initiële `ssh`-opdrachten uit op de host, vanuit de projectmap.

#### 1. SSH-hostpoorten controleren

Op de host:

```powershell
vagrant ssh-config client
vagrant ssh-config server3
```

Controleer per machine `HostName` en `Port`.

De tijdens deze test vastgestelde waarden waren:

| Machine | SSH-hostadres | SSH-hostpoort |
|---|---|---|
| client | `127.0.0.1` | `2211` |
| server3 | `127.0.0.1` | `2207` |

Gebruik bij gewijzigde portforwarding de actuele poorten uit `vagrant ssh-config`.

#### 2. Clientconfiguratie uitlezen

Uitvoeren op CLIENT. Een gewone gebruikerssessie volstaat voor `ipconfig /all`.

Als je nog niet op de client zit, voer op de host uit:

```powershell
ssh -p 2211 -l 'WS26-JD\p.jansen' -o PreferredAuthentications=password -o PasswordAuthentication=yes -o PubkeyAuthentication=no 127.0.0.1
```

Voer het huidige gebruikerswachtwoord uitsluitend bij de wachtwoordprompt in. Reset het wachtwoord niet opnieuw als aanmelden al werkt.

Alternatief, met het bestaande Vagrant-beheerdersaccount:

```powershell
vagrant ssh client
```

Start indien nodig PowerShell:

```cmd
powershell
```

Voer op CLIENT uit:

```powershell
hostname
whoami
ipconfig /all
```

Controleer dat `hostname` dit teruggeeft:

```text
client
```

Zoek in `ipconfig /all` de interne interface. In de geteste omgeving is dat `Ethernet 2`, met een adres uit `192.168.26.0/24`.

Verwar deze niet met de NAT-interface, die in de geteste omgeving `10.0.2.15` gebruikt.

##### Verwachte interne clientconfiguratie

| Onderdeel | Verwachte waarde |
|---|---|
| DHCP Enabled | `Yes` |
| IPv4 Address | `192.168.26.100` t/m `192.168.26.150` |
| Subnet Mask | `255.255.255.0` |
| DHCP Server | `192.168.26.30` |
| DNS Servers | `192.168.26.10` en `192.168.26.20` |
| Default Gateway | Leeg op de interne interface |
| Physical Address | Noteren voor vergelijking met de serverlease |
| Lease Obtained / Lease Expires | Aanwezig |

Noteer de actuele waarden:

```text
Interne interface:
Intern IPv4-adres:
Subnetmasker:
DHCP-server:
DNS-servers:
MAC-adres:
Lease verkregen:
Lease vervalt:
```

De eerder bevestigde waarden waren:

```text
Interne interface: Ethernet 2
Intern IPv4-adres: 192.168.26.100
Subnetmasker: 255.255.255.0
DHCP-server: 192.168.26.30
DNS-servers: 192.168.26.10 en 192.168.26.20
MAC-adres: 08-00-27-93-FF-25
```

Gebruik bij een nieuwe test de actuele uitvoer, niet automatisch deze historische waarden.

##### Beheerdersrechten en aanvullende PowerShell-controles

`ipconfig /all` is voor deze clientcontrole voldoende.

De eerdere aanvullende opdrachten `Get-NetIPInterface`, `Get-NetIPAddress` en `Get-DnsClientServerAddress` werden in de gewone SSH-gebruikerssessie geweigerd met:

```text
Cannot connect to CIM server. Access denied
```

Die weigering is geen mislukte DHCP-test. Geef de gewone gebruiker hiervoor geen extra rechten. De benodigde clientgegevens zijn met `ipconfig /all` uitgelezen.

#### 3. Terugkeren naar de host

Als je PowerShell binnen de SSH-sessie hebt gestart:

```powershell
exit
```

Daarna vanuit de SSH-shell:

```cmd
exit
```

Je moet opnieuw in de projectmap op je host staan voordat je de volgende SSH-verbinding opent.

#### 4. Aanmelden op server3 als domeinbeheerder

Op de host:

```powershell
ssh -p 2207 -l 'WS26-JD\Administrator' -o PreferredAuthentications=password -o PasswordAuthentication=yes -o PubkeyAuthentication=no 127.0.0.1
```

Voer het domeinbeheerderswachtwoord uitsluitend bij de wachtwoordprompt in.

Start PowerShell:

```cmd
powershell
```

#### 5. Actieve lease op server3 controleren

Voer dit blok op server3 uit als `WS26-JD\Administrator`.

Het blok vraagt het zojuist op CLIENT vastgestelde IP-adres en MAC-adres. Het controleert de lease zonder de lease te wijzigen.

```powershell
& {
    $ErrorActionPreference = "Stop"

    Import-Module DhcpServer

    Write-Output "===== Machine en account ====="
    hostname
    whoami

    if ($env:COMPUTERNAME -ine "SERVER3") {
        throw "Voer deze leasecontrole uit op SERVER3."
    }

    $ClientIP = (
        Read-Host "Intern IPv4-adres uit ipconfig /all op CLIENT"
    ).Trim()

    $ClientMAC = (
        Read-Host "MAC-adres van diezelfde interne clientinterface"
    ).Trim()

    $ParsedIP = [System.Net.IPAddress]::Parse($ClientIP)

    if (
        $ParsedIP.AddressFamily -ne
        [System.Net.Sockets.AddressFamily]::InterNetwork
    ) {
        throw "Voer een IPv4-adres in."
    }

    $Bytes = $ParsedIP.GetAddressBytes()

    if (
        $Bytes[0] -ne 192 -or
        $Bytes [ppl-ai-file-upload.s3.amazonaws](https://ppl-ai-file-upload.s3.amazonaws.com/web/direct-files/attachments/138683335/05fe9bad-37c7-4188-ba05-d639531026d2/Opdracht20Server-20II.pdf) -ne 168 -or
        $Bytes [learn.microsoft](https://learn.microsoft.com/en-us/windows-server/identity/ad-ds/active-directory-functional-levels) -ne 26 -or
        $Bytes [learn.microsoft](https://learn.microsoft.com/en-us/powershell/module/addsdeployment/install-addsforest?view=windowsserver2025-ps) -lt 100 -or
        $Bytes [learn.microsoft](https://learn.microsoft.com/en-us/powershell/module/addsdeployment/install-addsforest?view=windowsserver2025-ps) -gt 150
    ) {
        throw "Het clientadres valt niet binnen 192.168.26.100–192.168.26.150."
    }

    $NormalizedMAC = (
        $ClientMAC -replace '[-:\s]', ''
    ).ToUpperInvariant()

    if ($NormalizedMAC -notmatch '^[0-9A-F]{12}$') {
        throw "Ongeldig MAC-adres. Gebruik de Physical Address van de interne interface."
    }

    $Leases = @(
        Get-DhcpServerv4Lease `
            -ScopeId 192.168.26.0 `
            -ErrorAction Stop |
            Where-Object {
                $_.IPAddress.ToString() -eq $ParsedIP.ToString()
            }
    )

    if ($Leases.Count -ne 1) {
        throw "Verwacht precies één actieve lease voor $ClientIP; gevonden: $($Leases.Count)."
    }

    $Lease = $Leases[0]

    Write-Output "===== Gevonden serverlease ====="

    $Lease |
        Select-Object IPAddress,
            HostName,
            ClientId,
            AddressState,
            LeaseExpiryTime |
        Format-List

    $NormalizedClientId = (
        $Lease.ClientId -replace '[-:\s]', ''
    ).ToUpperInvariant()

    if ($Lease.AddressState.ToString() -ne "Active") {
        throw "De lease heeft niet de verwachte status Active."
    }

    if ($NormalizedClientId -ne $NormalizedMAC) {
        throw "De lease-ClientId komt niet overeen met de opgegeven interne client-MAC."
    }

    if (
        [string]::IsNullOrWhiteSpace($Lease.HostName) -or
        $Lease.HostName.TrimEnd(".") -ine "client.WS26-JD.hogent"
    ) {
        throw "De lease bevat niet de verwachte clienthostnaam."
    }

    Write-Output "PASS: actieve serverlease komt overeen met het interne IP-adres en de MAC van CLIENT."
}
```

Voor de eerder bevestigde omgeving voer je bij de prompts in:

```text
192.168.26.100
08-00-27-93-FF-25
```

Gebruik bij gewijzigde clientgegevens de actuele waarden uit stap 2.

Verwachte serveruitvoer:

```text
IPAddress    : 192.168.26.100
HostName     : client.WS26-JD.hogent
ClientId     : 08-00-27-93-ff-25
AddressState : Active

PASS: actieve serverlease komt overeen met het interne IP-adres en de MAC van CLIENT.
```

Als de controle faalt, noteer de fout en onderzoek het verschil. Maak geen handmatige lease aan om de test te laten slagen.


T20 is succesvol wanneer alle volgende punten zijn aangetoond:

- De interne clientinterface gebruikt DHCP.
- Het interne IPv4-adres ligt tussen `192.168.26.100` en `192.168.26.150`.
- Het subnetmasker is `255.255.255.0`.
- `ipconfig /all` vermeldt voor die interface DHCP-server `192.168.26.30`.
- De interne DNS-servers zijn `192.168.26.10` en `192.168.26.20`.
- De interne interface gebruikt geen APIPA-adres als vervanging voor de bedoelde lease.
- Op server3 bestaat een actieve lease voor hetzelfde IPv4-adres.
- De lease-ClientId komt overeen met de MAC van dezelfde interne clientinterface.
- De lease verwijst naar `client.WS26-JD.hogent`.
- De client- en serveruitvoer zijn als bewijs bewaard.

Vergelijk leasevervaltijden alleen met aandacht voor tijdzone en moment van uitlezen. Noteer verschillen; het directe koppelbewijs bestaat uit hetzelfde IP-adres, dezelfde clientidentiteit en de actieve leasestatus.

- Een bestaande geldige lease is voldoende voor deze test en voor de video.
- Voer geen algemene `ipconfig /release` uit.
- Voer niet onnodig `ipconfig /renew` uit.
- Verander geen DHCP-, DNS- of firewallinstellingen voor een uitleescontrole.
- Geef gewone gebruikers geen extra rechten om aanvullende netwerkcmdlets te laten werken.
- Wijzig of verwijder geen bestaande lease om bewijs te creëren.

Status: SUCCESVOL

## 10. Certification Authority en automatisch vertrouwen

### T21 — CA en Web Enrollment geïnstalleerd

Op server3:

```powershell
Get-WindowsFeature -Name AD-Certificate, ADCS-Cert-Authority, ADCS-Web-Enrollment |
    Select-Object Name, DisplayName, InstallState

Get-Service -Name CertSvc, W3SVC |
    Select-Object Name, Status

certutil.exe -getconfig
```

Controleer zo nodig de beschikbare namen op deze server:

```powershell
Get-WindowsFeature |
    Where-Object {
        $_.Name -like "*Cert*" -or
        $_.Name -like "*ADCS*"
    } |
    Select-Object Name, DisplayName, InstallState
```

Acceptatiecriteria:

- Certificate Authority-role service geïnstalleerd.
- Web Enrollment-role service geïnstalleerd.
- CertSvc en IIS draaien.
- CA-configuratie verwijst naar de bedoelde CA.

Aanvullend:

```powershell
Get-ItemProperty `
    "HKLM:\SYSTEM\CurrentControlSet\Services\CertSvc\Configuration" |
    Select-Object Active

Get-ItemProperty `
    "HKLM:\SYSTEM\CurrentControlSet\Services\CertSvc\Configuration\WS26-JD-Root-CA" |
    Select-Object CAType
```

Voor een Enterprise Root CA wordt `CAType = 0` verwacht.

Status: NIET GETEST

### T22 — Actueel rootcertificaat vaststellen

Op server3:

```powershell
$RootPath = "C:\LabCertificates\WS26-JD-Root-CA.cer"

$RootCertificate =
    [System.Security.Cryptography.X509Certificates.X509Certificate2]::new(
        $RootPath
    )

try {
    $RootCertificate |
        Format-List Subject, Issuer, Thumbprint, NotBefore, NotAfter

    Write-Output "Actuele thumbprint: $($RootCertificate.Thumbprint)"
}
finally {
    $RootCertificate.Dispose()
}
```

Acceptatiecriteria:

- Bestand bestaat.
- Verwachte CA-naam.
- Subject en issuer passen bij de eigen root-CA.
- Geldig op de testdatum.
- Noteer de actuele thumbprint.

Gebruik geen oude vaste thumbprint uit historische documentatie.

Status: NIET GETEST

### T23 — GPO bestaat, is gekoppeld en bevat het certificaat

Uitvoeren op server1 als **`WS26-JD\Administrator`**. Alle opdrachten lezen alleen gegevens uit.

#### Aanmelden vanaf de host

```powershell
ssh -p 2222 -l 'WS26-JD\Administrator' -o PreferredAuthentications=password -o PasswordAuthentication=yes -o PubkeyAuthentication=no 127.0.0.1
```

Start PowerShell:

```cmd
powershell
```

#### GPO, domeinkoppeling en certificaatblob controleren

```powershell
& {
    $ErrorActionPreference = "Stop"

    Import-Module ActiveDirectory
    Import-Module GroupPolicy

    $Thumbprint = "344944DE76805C57B48E01B14E7000C84ABCD7FA"

    $Gpos = @(
        Get-GPO -All |
            Where-Object DisplayName -eq "WS26 - Vertrouw Root CA"
    )

    if ($Gpos.Count -ne 1) {
        throw "Verwacht precies één CA-trust-GPO."
    }

    $Gpo = $Gpos[0]

    $Gpo |
        Select-Object DisplayName, Id, GpoStatus |
        Format-List

    if ($Gpo.GpoStatus.ToString() -notin @(
        "AllSettingsEnabled", "UserSettingsDisabled"
    )) {
        throw "Computerinstellingen zijn uitgeschakeld."
    }

    $Links = @(
        (Get-GPInheritance -Target (Get-ADDomain).DistinguishedName).GpoLinks |
            Where-Object { $_.GpoId -eq $Gpo.Id }
    )

    $Links |
        Select-Object DisplayName, Enabled, Enforced |
        Format-List

    if ($Links.Count -ne 1 -or -not $Links[0].Enabled) {
        throw "De bedoelde domeinkoppeling ontbreekt of is uitgeschakeld."
    }

    $Parameters = @{
        Guid      = $Gpo.Id
        Key       = "HKLM\Software\Policies\Microsoft\SystemCertificates\Root\Certificates\$Thumbprint"
        ValueName = "Blob"
    }

    $Setting = Get-GPRegistryValue @Parameters
    $BlobLength = @($Setting.Value).Count

    if (
        $Setting.Type.ToString() -ne "Binary" -or
        $BlobLength -eq 0
    ) {
        throw "Geen niet-lege binaire certificaatblob gevonden."
    }

    [PSCustomObject]@{
        Thumbprint      = $Thumbprint
        RegistryType    = $Setting.Type
        BlobLengthBytes = $BlobLength
    } | Format-List

    Write-Output "PASS: GPO, domeinkoppeling en certificaatblob bevestigd."
}
```

Gebruik bij een nieuwe CA-installatie de opnieuw vastgestelde actuele thumbprint.

#### GPO-toepassing controleren

Op server1, server2, server3 en CLIENT, telkens in een verhoogde beheerderssessie:

```powershell
hostname
gpresult.exe /scope computer /r
```

Verwacht onder `Applied Group Policy Objects`:

```text
WS26 - Vertrouw Root CA
```

Dit toepassingsbewijs is ook bij T24 vastgelegd.

#### Acceptatiecriteria

- Precies één bedoelde GPO.
- Computerinstellingen ingeschakeld.
- Domeinkoppeling ingeschakeld.
- Niet-lege binaire `Blob` onder de actuele CA-thumbprint.
- GPO als toegepast getoond op alle vier machines.

Status: SUCCESVOL

### T24 — Vertrouwen op alle vier domeinmachines

Voer dit blok afzonderlijk uit op server1, server2, server3 en de client.

Dit blok controleert lokaal het rootcertificaat en de beleidsopslag met de vooraf vastgestelde actuele CA-thumbprint. Het importeert of wijzigt niets.

```powershell
& {
    $ErrorActionPreference = "Stop"

    $Thumbprint = "344944DE76805C57B48E01B14E7000C84ABCD7FA"

    $Trusted = Get-Item `
        -LiteralPath "Cert:\LocalMachine\Root\$Thumbprint" `
        -ErrorAction Stop

    $Now = Get-Date

    if (
        $Trusted.NotBefore -gt $Now -or
        $Trusted.NotAfter -le $Now
    ) {
        throw "Het rootcertificaat is niet geldig op de testdatum."
    }

    $PolicyPath =
        "HKLM:\SOFTWARE\Policies\Microsoft\SystemCertificates\" +
        "Root\Certificates\$Thumbprint"

    $Policy = Get-ItemProperty `
        -LiteralPath $PolicyPath `
        -Name Blob `
        -ErrorAction Stop

    if (@($Policy.Blob).Count -eq 0) {
        throw "Lege certificaatblob in de beleidsopslag."
    }

    [PSCustomObject]@{
        Computer                 = $env:COMPUTERNAME
        Thumbprint               = $Trusted.Thumbprint
        TrustedRootPresent       = $true
        PolicyCertificatePresent = $true
        CertificateCurrentlyValid = $true
    } | Format-List
}
```

Controleer daarnaast op iedere machine:

```powershell
gpresult.exe /scope computer /r
```

Acceptatiecriteria:

- Exact dezelfde actuele CA-thumbprint aanwezig in LocalMachine\Root.
- Certificaat aanwezig in de computerbeleidsopslag.
- De bedoelde GPO wordt als toegepast getoond.
- Geen handmatige certificaatimport nodig.

Als de GPO nog niet is toegepast:

- Noteer dat de oorspronkelijke controle faalde.
- Onderzoek domeinlidmaatschap, bereikbaarheid en GPO-toepassing.
- Een latere `gpupdate` mag als herstelactie worden uitgevoerd,
  maar noteer die manuele actie afzonderlijk.

Status per machine:

| Machine | Trust | Policy | GPO toegepast | Eindstatus |
|---|---|---|---|---|
| server1 | Niet getest | Niet getest | Niet getest | NIET GETEST |
| server2 | Niet getest | Niet getest | Niet getest | NIET GETEST |
| server3 | Niet getest | Niet getest | Niet getest | NIET GETEST |
| client | Niet getest | Niet getest | Niet getest | NIET GETEST |

### T25 — HTTPS-binding en webservercertificaat

Op server3:

```powershell
Import-Module WebAdministration

Get-WebBinding -Name "Default Web Site" -Protocol https |
    Format-List protocol, bindingInformation, certificateHash, certificateStoreName

Get-ChildItem Cert:\LocalMachine\My |
    Where-Object {
        $_.Subject -eq "CN=server3.WS26-JD.hogent"
    } |
    Format-List Subject, Issuer, Thumbprint,
        HasPrivateKey, NotBefore, NotAfter,
        DnsNameList, EnhancedKeyUsageList
```

Acceptatiecriteria:

- HTTPS-binding op poort 443.
- Binding verwijst naar het bedoelde certificaat.
- Private key aanwezig.
- Certificaat geldig.
- FQDN aanwezig in de certificaatnamen.
- Geschikt voor Server Authentication.
- Uitgegeven door de bedoelde CA.

Status: NIET GETEST

### T26 — Web Enrollment vanaf de client

Uitvoeren op **CLIENT** als `client\vagrant`. Voor de HTTPS-aanvraag worden afzonderlijk de credentials van `WS26-JD\Administrator` gebruikt.

De test leest alleen webpagina’s op. Er worden geen certificaten aangevraagd of instellingen gewijzigd.

#### Aanmelden vanaf de host

```powershell
vagrant ssh client
```

Start PowerShell:

```cmd
powershell
```

#### HTTP-redirect en HTTPS-pagina controleren

```powershell
& {
    $ErrorActionPreference = "Stop"

    hostname
    whoami

    if ($env:COMPUTERNAME -ine "CLIENT") {
        throw "Voer deze test uit op CLIENT."
    }

    $HttpUrl = "http://server3.WS26-JD.hogent/CertSrv/"
    $HttpsUrl = "https://server3.WS26-JD.hogent/certsrv/Default.asp"

    $Request = [System.Net.HttpWebRequest]::Create($HttpUrl)
    $Request.AllowAutoRedirect = $false
    $Request.Timeout = 30000

    $Response = $Request.GetResponse()

    try {
        $HttpStatus = [int]$Response.StatusCode
        $Location = $Response.Headers["Location"]

        [PSCustomObject]@{
            HTTPStatus = $HttpStatus
            Location   = $Location
        } | Format-List

        if ($HttpStatus -ne 302) {
            throw "Verwacht HTTP 302."
        }

        if ([string]::IsNullOrWhiteSpace($Location)) {
            throw "Redirectbestemming ontbreekt."
        }

        $RedirectUri = [uri]::new([uri]$HttpUrl, $Location)

        if ($RedirectUri.AbsoluteUri -ine $HttpsUrl) {
            throw "Onverwachte redirectbestemming: $RedirectUri"
        }
    }
    finally {
        $Response.Close()
    }

    $Password = Read-Host `
        "Wachtwoord voor WS26-JD\Administrator" `
        -AsSecureString

    $Credential = [PSCredential]::new(
        "WS26-JD\Administrator",
        $Password
    )

    $Page = Invoke-WebRequest `
        -Uri $HttpsUrl `
        -Credential $Credential `
        -UseBasicParsing `
        -MaximumRedirection 0 `
        -TimeoutSec 30 `
        -ErrorAction Stop

    $EnrollmentFound = (
        $Page.Content -match "Microsoft Active Directory Certificate Services"
    )

    [PSCustomObject]@{
        Computer           = $env:COMPUTERNAME
        HTTPSStatus        = $Page.StatusCode
        WebEnrollmentFound = $EnrollmentFound
    } | Format-List

    if ($Page.StatusCode -ne 200 -or -not $EnrollmentFound) {
        throw "De verwachte Web Enrollment-pagina is niet bevestigd."
    }

    Write-Output "PASS: Web Enrollment vanaf CLIENT bereikbaar via HTTP-redirect en HTTPS."
}
```

Voer het domeinbeheerderswachtwoord uitsluitend bij de verborgen prompt in. Neem het niet op in het testdocument.

#### Acceptatiecriteria

- De controle is daadwerkelijk uitgevoerd op CLIENT.
- De HTTP-ingang geeft status `302`.
- De redirect verwijst naar de bedoelde HTTPS-bestemming.
- De HTTPS-aanvraag met domeincredentials geeft status `200`.
- `WebEnrollmentFound` is `True`.
- Certificaatvalidatie wordt niet omzeild.

#### Aanvullende verificatie vanaf server1

Optioneel uitvoeren op de host:

```powershell
vagrant provision server1 --provision-with server1-verify-web-enrollment
```

Dit is een gerichte verificatieprovisioner. Deze test vanaf server1 vervangt het bewijs vanaf CLIENT niet.

Een bereikbare Web Enrollment-pagina bewijst niet dat iedere gebruiker ieder certificaatsjabloon kan aanvragen. Een certificaataanvraag is een afzonderlijke test; verwijder daarvoor geen werkend HTTPS-certificaat.

Status: SUCCESVOL

## 11. IIS en intranet

### T27 — IIS-rol, website en inhoud

Op server1:

```powershell
Get-WindowsFeature -Name Web-Server |
    Select-Object Name, InstallState

Get-Service W3SVC |
    Select-Object Name, Status

Import-Module WebAdministration

Get-Website |
    Select-Object Name, State, PhysicalPath

Get-WebBinding -Name "Default Web Site" |
    Select-Object protocol, bindingInformation
```

Lokale controle:

```powershell
$Page = Invoke-WebRequest `
    -Uri "http://localhost/default.htm" `
    -UseBasicParsing `
    -TimeoutSec 30 `
    -ErrorAction Stop

[PSCustomObject]@{
    StatusCode = $Page.StatusCode
    HelloWorldFound = ($Page.Content -match "Hello World")
}
```

Acceptatiecriteria:

- IIS geïnstalleerd.
- Website gestart.
- HTTP-binding op poort 80.
- HTTP 200.
- Hello World aanwezig.

Status: NIET GETEST

### T28 — Intranet vanaf client via beide DNS-servers

Op de client:

```powershell
foreach ($DnsServer in @("192.168.26.10", "192.168.26.20")) {
    Resolve-DnsName `
        -Name "intranet.WS26-JD.hogent" `
        -Server $DnsServer `
        -Type A `
        -DnsOnly `
        -ErrorAction Stop
}

$Page = Invoke-WebRequest `
    -Uri "http://intranet.WS26-JD.hogent" `
    -UseBasicParsing `
    -TimeoutSec 30 `
    -ErrorAction Stop

[PSCustomObject]@{
    StatusCode = $Page.StatusCode
    HelloWorldFound = ($Page.Content -match "Hello World")
}
```

Acceptatiecriteria:

- Beide DNS-servers geven `192.168.26.10`.
- HTTP 200.
- Hello World zichtbaar.
- Geen hosts-file-workaround nodig.

Status: NIET GETEST

## 12. RSAT en beheer vanaf de client

### T29 — Alleen benodigde RSAT-tools

Uitvoeren op **CLIENT** als lokaal beheerder `client\vagrant`, niet als gewone domeingebruiker.

#### Aanmelden vanaf de host

```powershell
vagrant ssh client
```

Start PowerShell:

```cmd
powershell
```

#### Geïnstalleerde RSAT-tools controleren

Op CLIENT:

```powershell
hostname
whoami

Get-WindowsCapability -Online |
    Where-Object {
        $_.Name -like "Rsat.*" -and
        $_.State -eq "Installed"
    } |
    Select-Object Name, State |
    Format-Table -AutoSize
```

Verwacht:

```text
Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0    Installed
Rsat.DHCP.Tools~~~~0.0.1.0                      Installed
Rsat.Dns.Tools~~~~0.0.1.0                       Installed
Rsat.GroupPolicy.Management.Tools~~~~0.0.1.0    Installed
Rsat.ServerManager.Tools~~~~0.0.1.0             Installed
```

De eerste vier onderdelen zijn expliciet geselecteerd in het installatiescript. Server Manager is de eerder vastgestelde verklaarbare afhankelijkheid.

#### Acceptatiecriteria

- De vier vereiste RSAT-tools hebben status `Installed`.
- Eventuele extra RSAT-onderdelen zijn verklaarbaar.

Voer voor deze bewijscontrole geen herinstallatie uit. Functioneel remote beheer is een afzonderlijke test.

Status: SUCCESVOL

## 13. Firewall

### T31 — Effectief profielbeleid

Op server1, server2, server3 en aanvullend de client:

```powershell
Get-NetConnectionProfile |
    Select-Object InterfaceAlias, NetworkCategory

Get-NetFirewallProfile -PolicyStore ActiveStore |
    Select-Object Name, Enabled,
        DefaultInboundAction,
        DefaultOutboundAction
```

Acceptatiecriteria voor de servers:

- Firewall ingeschakeld op alle profielen.
- Effectieve standaardactie inkomend: Block.
- Uitgaand beleid volgens het gedocumenteerde ontwerp.
- In dit project wordt uitgaand Allow verwacht.
- Geen eindconfiguratie met uitgeschakelde firewall.

Status: NIET GETEST

### T32 — Effectieve inkomende toestemmingen beoordelen

#### Doel en accounts

Beoordelen of de effectieve inkomende Allow-regels passen bij het labontwerp, zonder onverklaarde brede uitzonderingen.

| Controle | Machine | Account |
|---|---|---|
| Lokale firewallregels en profielen uitlezen | server1 | `WS26-JD\vagrant` via `vagrant ssh server1` |
| Lokale firewallregels en profielen uitlezen | server2 | `server2\vagrant` via `vagrant ssh server2` |
| Lokale firewallregels en profielen uitlezen | server3 | `server3\vagrant` via `vagrant ssh server3` |
| Extern DHCP-beheer testen | CLIENT | **`WS26-JD\Administrator`** |
| Externe CA-RPC-toegang testen | server1 | `WS26-JD\Administrator` |
| Web Enrollment testen | CLIENT | `WS26-JD\Administrator` |

Gebruik voor lokale firewallcontroles een verhoogde beheerderssessie. Gebruik voor extern DHCP-beheer niet het lokale `client\vagrant`-account.

Alle testblokken hieronder lezen alleen gegevens uit. De eerder uitgevoerde firewallwijziging wordt apart beschreven en hoeft niet bij iedere test te worden herhaald.

#### 1. Aanmelden voor lokale firewallcontroles

Voer vanaf de host telkens één van deze opdrachten uit:

```powershell
vagrant ssh server1
vagrant ssh server2
vagrant ssh server3
```

Start binnen de gekozen VM PowerShell:

```cmd
powershell
```

Controleer bij iedere sessie:

```powershell
hostname
whoami
```

Terug naar de host na een controle:

```powershell
exit
```

Daarna vanuit de SSH-shell:

```cmd
exit
```

#### 2. Effectieve profielen en inkomende Allow-regels uitlezen

Uitvoeren op alle drie servers, telkens met het beheerdersaccount uit de tabel.

```powershell
& {
    $ErrorActionPreference = "Stop"

    hostname
    whoami

    Write-Output "===== Effectieve firewallprofielen ====="

    Get-NetFirewallProfile -PolicyStore ActiveStore |
        Select-Object Name, Enabled,
            DefaultInboundAction, DefaultOutboundAction |
        Format-Table -AutoSize

    $Rules = @(
        Get-NetFirewallRule -PolicyStore ActiveStore |
            Where-Object {
                $_.Enabled -eq "True" -and
                $_.Direction -eq "Inbound" -and
                $_.Action -eq "Allow"
            }
    )

    $Overview = foreach ($Rule in $Rules) {
        $Port = $Rule | Get-NetFirewallPortFilter
        $Address = $Rule | Get-NetFirewallAddressFilter
        $Interface = $Rule | Get-NetFirewallInterfaceFilter
        $Service = $Rule | Get-NetFirewallServiceFilter
        $Application = $Rule | Get-NetFirewallApplicationFilter

        [PSCustomObject]@{
            Computer         = $env:COMPUTERNAME
            Name             = $Rule.Name
            DisplayName      = $Rule.DisplayName
            Profile          = $Rule.Profile
            Protocol         = $Port.Protocol
            LocalPort        = $Port.LocalPort -join ","
            RemotePort       = $Port.RemotePort -join ","
            IcmpType         = $Port.IcmpType -join ","
            LocalAddress     = $Address.LocalAddress -join ","
            RemoteAddress    = $Address.RemoteAddress -join ","
            Interface        = $Interface.InterfaceAlias -join ","
            Service          = $Service.Service
            Program          = $Application.Program
            Package          = $Application.Package
            PolicySource     = $Rule.PolicyStoreSource
            PolicySourceType = $Rule.PolicyStoreSourceType
        }
    }

    $Overview |
        Sort-Object Name |
        Format-List |
        Out-String -Width 240 |
        Write-Output

    Write-Output "Aantal ingeschakelde inkomende Allow-regels: $($Rules.Count)"
}
```

Gebruik `Format-List` zodat filters niet door smalle tabellen worden verborgen.

Beoordeel:

- NAT-beheerregels: juiste interface, poorten en bron `10.0.2.2`.
- Interne diensten: juiste interface en bronnetwerk `192.168.26.0/24`, waar passend.
- Server1-regels: verklaarbaar vanuit AD DS, DNS, IIS en beheer.
- Server2-regels: verklaarbaar vanuit secundaire DNS en beheer.
- Server3-regels: verklaarbaar vanuit DHCP, CA, Web Enrollment en beheer.
- Ingebouwde basisregels: beoordeel protocol, ICMP-type, service en programma.
- Geen onverklaarde algemene toestemmingen.

Een vermelding van `Any` in één filter is niet automatisch een Allow-All-regel. Beoordeel alle filters gezamenlijk.

#### 3. Brede server3-regel controleren

Uitvoeren op server3 als lokaal beheerder `server3\vagrant`:

```powershell
& {
    $ErrorActionPreference = "Stop"

    hostname
    whoami

    $Rule = Get-NetFirewallRule `
        -PolicyStore ActiveStore `
        -Name "WS2-Managed-Server3-RPC-Dynamic" `
        -ErrorAction Stop

    $Rule |
        Select-Object Name, Enabled |
        Format-List

    if ($Rule.Enabled.ToString() -ne "False") {
        throw "De brede dynamische TCP-regel staat nog ingeschakeld."
    }

    Write-Output "PASS: de brede server3-regel is uitgeschakeld."
}
```

Verwacht:

```text
Name    : WS2-Managed-Server3-RPC-Dynamic
Enabled : False
```

De regel is tijdens de eerdere aanscherping uit de gewenste configuratie in `scripts/configure-firewall.ps1` verwijderd. De opruimlus heeft de bestaande regel uitgeschakeld.

Bij een volledig nieuwe uitrol kan de regel ontbreken. Dat is eveneens correct: beoordeel dan dat de ongewenste toestemming afwezig is.

#### 4. Extern DHCP-beheer vanaf CLIENT testen

Uitvoeren op CLIENT als `WS26-JD\Administrator`.

Aanmelden vanaf de host:

```powershell
ssh -p 2211 -l 'WS26-JD\Administrator' -o PreferredAuthentications=password -o PasswordAuthentication=yes -o PubkeyAuthentication=no 127.0.0.1
```

Start PowerShell:

```cmd
powershell
```

Voer uit:

```powershell
& {
    $ErrorActionPreference = "Stop"

    hostname
    whoami

    $Identity = [Security.Principal.WindowsIdentity]::GetCurrent().Name

    if (
        $env:COMPUTERNAME -ine "CLIENT" -or
        $Identity -ine "WS26-JD\Administrator"
    ) {
        throw "Voer deze controle uit op CLIENT als WS26-JD\Administrator."
    }

    Import-Module DhcpServer -ErrorAction Stop

    $Scope = Get-DhcpServerv4Scope `
        -ComputerName "server3.WS26-JD.hogent" `
        -ScopeId 192.168.26.0 `
        -ErrorAction Stop

    $Scope |
        Select-Object ScopeId, Name, State, StartRange, EndRange |
        Format-List

    if ($Scope.State.ToString() -ne "Active") {
        throw "De verwachte DHCP-scope is niet actief."
    }

    Write-Output "PASS: extern DHCP-beheer vanaf CLIENT werkt."
}
```

Verwacht een actieve scope `192.168.26.0`, met bereik `.100` tot en met `.200`.

Een rechtenfout onder `client\vagrant` is geen vergelijkbare test: herhaal de controle met het voorgeschreven domeinaccount.

#### 5. CA-RPC vanaf server1 testen

Uitvoeren op server1 als `WS26-JD\Administrator`.

Aanmelden vanaf de host:

```powershell
ssh -p 2222 -l 'WS26-JD\Administrator' -o PreferredAuthentications=password -o PasswordAuthentication=yes -o PubkeyAuthentication=no 127.0.0.1
```

Start PowerShell:

```cmd
powershell
```

Voer uit:

```powershell
& {
    $ErrorActionPreference = "Stop"

    hostname
    whoami

    $Identity = [Security.Principal.WindowsIdentity]::GetCurrent().Name

    if (
        $env:COMPUTERNAME -ine "SERVER1" -or
        $Identity -ine "WS26-JD\Administrator"
    ) {
        throw "Voer deze controle uit op SERVER1 als WS26-JD\Administrator."
    }

    certutil.exe `
        -config "server3.WS26-JD.hogent\WS26-JD-Root-CA" `
        -ping

    if ($LASTEXITCODE -ne 0) {
        throw "De externe CA-RPC-controle is mislukt."
    }

    Write-Output "PASS: CA-RPC vanaf SERVER1 werkt."
}
```

Verwacht:

```text
ICertRequest2 interface is alive
CertUtil: -ping command completed successfully.
```

#### 6. Web Enrollment vanaf CLIENT testen

Uitvoeren op CLIENT als `WS26-JD\Administrator`.

Aanmelden vanaf de host:

```powershell
ssh -p 2211 -l 'WS26-JD\Administrator' -o PreferredAuthentications=password -o PasswordAuthentication=yes -o PubkeyAuthentication=no 127.0.0.1
```

Start PowerShell:

```cmd
powershell
```

Voer het volledige controleblok van T26 uit.

Verwacht:

```text
HTTPStatus         : 302
HTTPSStatus        : 200
WebEnrollmentFound : True
```

Certificaatvalidatie mag niet worden omzeild. De test vraagt geen nieuw certificaat aan.

#### 7. Veiligheids- en herstelafspraken

- Schakel de firewall niet uit om een test te laten slagen.
- Voer het firewallconfiguratiescript niet rechtstreeks uit via SSH: het script vereist de NAT-WinRM-verbinding van de Vagrant-provisioner.
- Een noodzakelijke configuratiewijziging wordt gericht vanaf de host toegepast:

```powershell
vagrant provision server3 --provision-with server3-firewall
```

Dit is een wijzigingsactie, geen uitleescontrole. Voer deze niet opnieuw uit als alleen bewijs nodig is.

- Bewaar bij wijzigingen de door het script gemaakte back-uplocatie.
- Het script herstelt bij een interne uitvoeringsfout; een later ontdekte functionele storing wordt niet automatisch herkend.
- Vergelijk bij wijzigingen de functionele resultaten vóór en na de wijziging met dezelfde machines en accounts.

#### Acceptatiecriteria

- Alle effectieve inkomende Allow-regels op de drie servers zijn beoordeeld.
- Alleen verklaarbare toestemmingen blijven actief.
- Beheerregels en interne diensten zijn beperkt volgens het labontwerp.
- Geen algemene Allow-All-regel als vervanging voor rolgebonden regels.
- Dynamische RPC-regels zijn beoordeeld inclusief service- en programmafilters.
- Eigen, ingebouwde en eventuele GPO-regels zijn meegenomen.
- De brede algemene server3-regel is uitgeschakeld of afwezig.
- Firewallprofielen blijven ingeschakeld met inkomend `Block`.
- Extern DHCP-beheer, CA-RPC, Web Enrollment en SSH werken na de aanscherping.

#### Vastgesteld resultaat

Status: SUCCESVOL

### T33 — Functionele verbindingen met actieve firewall

Op de client:

```powershell
Test-NetConnection server1.WS26-JD.hogent -Port 80
Test-NetConnection server1.WS26-JD.hogent -Port 53
Test-NetConnection server2.WS26-JD.hogent -Port 53
Test-NetConnection server3.WS26-JD.hogent -Port 443
```

Daarnaast dienen de eerdere functionele tests als bewijs:

- DNS-query's naar beide DNS-servers.
- Automatische zone transfer.
- Echte DHCP-lease.
- RSAT-beheer.
- Intranet.
- Web Enrollment.
- SSH vanaf de host.

Let op:

- `Test-NetConnection -Port` controleert TCP, niet UDP.
- Een geslaagde TCP-53-test bewijst niet zelfstandig dat UDP-DNS werkt.
- Een mislukte verbinding naar een poort zonder luisterende service
  bewijst niet dat de firewall die verbinding heeft geblokkeerd.
- SSH kan in dit project via NAT toegestaan zijn en via Host-Only juist niet.
  Test dus de bedoelde toegangsroute.

Status: NIET GETEST

## 14. Aanvullende kwaliteitscontroles

Deze controles zijn nuttig voor betrouwbaarheid.
Maak onderscheid tussen harde opdrachtvereisten en extra kwaliteitsbewijs.

### T33 — Functionele verbindingen met actieve firewall

#### Uitvoerlocaties en accounts

| Controle | Machine | Account |
|---|---|---|
| TCP, DNS, intranet en extern DHCP-beheer | CLIENT | **`WS26-JD\Administrator`** |
| Web Enrollment | CLIENT | `WS26-JD\Administrator` |
| Firewallprofielen en lokale leasecontrole | Iedere server | Lokaal Vagrant-beheerdersaccount; op server1 `WS26-JD\vagrant` |
| Automatische zone transfer | server1 | `WS26-JD\Administrator`, volgens T17 |
| SSH-bereikbaarheid | Vanaf de host | Vagrant-account via `vagrant ssh` |

Alle controles hieronder lezen alleen gegevens uit. Alleen de afzonderlijke T17-transferdemo maakt en verwijdert een eigen tijdelijk DNS-record.

#### 1. Aanmelden op CLIENT als domeinbeheerder

Op de host, vanuit de projectmap:

```powershell
vagrant ssh-config client
```

Gebruik de actuele SSH-hostpoort. Tijdens de test was dat `2211`:

```powershell
ssh -p 2211 -l 'WS26-JD\Administrator' -o PreferredAuthentications=password -o PasswordAuthentication=yes -o PubkeyAuthentication=no 127.0.0.1
```

Start PowerShell:

```cmd
powershell
```

#### 2. TCP, DNS, intranet en extern DHCP-beheer testen

Uitvoeren op CLIENT als `WS26-JD\Administrator`:

```powershell
& {
    $ErrorActionPreference = "Stop"

    hostname
    whoami

    $Identity = [Security.Principal.WindowsIdentity]::GetCurrent().Name

    if (
        $env:COMPUTERNAME -ine "CLIENT" -or
        $Identity -ine "WS26-JD\Administrator"
    ) {
        throw "Voer deze controle uit op CLIENT als WS26-JD\Administrator."
    }

    Write-Output "===== TCP-verbindingen ====="

    $Targets = @(
        @{ Server = "server1.WS26-JD.hogent"; Port = 80 }
        @{ Server = "server1.WS26-JD.hogent"; Port = 53 }
        @{ Server = "server2.WS26-JD.hogent"; Port = 53 }
        @{ Server = "server3.WS26-JD.hogent"; Port = 443 }
    )

    $Results = @(
        foreach ($Target in $Targets) {
            $Test = Test-NetConnection `
                -ComputerName $Target.Server `
                -Port $Target.Port `
                -InformationLevel Detailed

            [PSCustomObject]@{
                Server           = $Target.Server
                RemoteAddress    = $Test.RemoteAddress
                Port             = $Target.Port
                Interface        = $Test.InterfaceAlias
                SourceAddress    = $Test.SourceAddress
                TcpTestSucceeded = $Test.TcpTestSucceeded
            }
        }
    )

    $Results | Format-List

    if (@($Results | Where-Object {
        -not $_.TcpTestSucceeded
    }).Count -gt 0) {
        throw "Minstens één TCP-verbinding is mislukt."
    }

    Write-Output "===== DNS-query naar beide DNS-servers ====="

    foreach ($DnsServer in @("192.168.26.10", "192.168.26.20")) {
        Write-Output "DNS-server: $DnsServer"

        $Answers = @(
            Resolve-DnsName `
                -Name "intranet.WS26-JD.hogent" `
                -Server $DnsServer `
                -Type A `
                -DnsOnly `
                -ErrorAction Stop
        )

        $Answers |
            Select-Object Name, Type, IPAddress |
            Format-Table -AutoSize

        $Addresses = @(
            $Answers |
                Where-Object { $_.Type -eq "A" } |
                Select-Object -ExpandProperty IPAddress
        )

        if (
            $Addresses.Count -ne 1 -or
            $Addresses[0] -ne "192.168.26.10"
        ) {
            throw "Onverwacht DNS-antwoord van $DnsServer."
        }
    }

    Write-Output "===== Intranetinhoud ====="

    $Page = Invoke-WebRequest `
        -Uri "http://intranet.WS26-JD.hogent" `
        -UseBasicParsing `
        -TimeoutSec 30 `
        -ErrorAction Stop

    $HelloWorldFound = $Page.Content -match "Hello World"

    [PSCustomObject]@{
        StatusCode      = $Page.StatusCode
        HelloWorldFound = $HelloWorldFound
    } | Format-List

    if ($Page.StatusCode -ne 200 -or -not $HelloWorldFound) {
        throw "De intranetcontrole is mislukt."
    }

    Write-Output "===== Extern DHCP-beheer via RSAT ====="

    Import-Module DhcpServer -ErrorAction Stop

    $Scope = Get-DhcpServerv4Scope `
        -ComputerName "server3.WS26-JD.hogent" `
        -ScopeId 192.168.26.0 `
        -ErrorAction Stop

    $Scope |
        Select-Object ScopeId, Name, State, StartRange, EndRange |
        Format-List

    if ($Scope.State.ToString() -ne "Active") {
        throw "De verwachte DHCP-scope is niet actief."
    }

    Write-Output "PASS: TCP, DNS, intranet en extern DHCP-beheer werken."
}
```

Verwacht:

- Alle vier `TcpTestSucceeded`-waarden zijn `True`.
- De verbindingen gebruiken de interne clientinterface en het interne bronadres.
- Beide DNS-servers geven voor intranet `192.168.26.10`.
- Intranet geeft HTTP `200` en `HelloWorldFound=True`.
- De externe DHCP-scope heeft status `Active`.

#### 3. Web Enrollment controleren

Blijf op CLIENT als `WS26-JD\Administrator`.

Voer het volledige T26-controleblok uit. Dat controleert:

```text
HTTPStatus         : 302
HTTPSStatus        : 200
WebEnrollmentFound : True
```

Gebruik bij de verborgen wachtwoordprompt het domein-Administratorwachtwoord. Schakel certificaatvalidatie niet uit.

Het volledige T26-resultaat dient als aanvullend T33-bewijs; een TCP-443-test alleen vervangt deze paginacontrole niet.

#### 4. Echte clientlease controleren

Op CLIENT als `WS26-JD\Administrator`:

```powershell
hostname
ipconfig /all
```

Controleer op de interne interface:

- DHCP ingeschakeld.
- Adres tussen `192.168.26.100` en `192.168.26.150`.
- DHCP-server `192.168.26.30`.
- DNS-servers `192.168.26.10` en `192.168.26.20`.
- MAC-adres overeenkomend met de serverlease.

Vanuit dezelfde client-PowerShell kun je de serverleases uitlezen:

```powershell
Import-Module DhcpServer -ErrorAction Stop

Get-DhcpServerv4Lease `
    -ComputerName "server3.WS26-JD.hogent" `
    -ScopeId 192.168.26.0 `
    -ErrorAction Stop |
    Select-Object IPAddress, HostName, ClientId,
        AddressState, LeaseExpiryTime |
    Format-List
```

Vergelijk IP-adres en MAC/ClientId. Verwacht voor CLIENT een actieve, overeenkomende lease. Gebruik het volledige T20-resultaat als bewijs.

Voer geen `ipconfig /release` of `/renew` uit voor deze controle.

#### 5. SSH en actieve serverfirewalls controleren

Verlaat de client-PowerShell:

```powershell
exit
```

Daarna vanuit de SSH-shell:

```cmd
exit
```

Voer op de host telkens één opdracht uit:

```powershell
vagrant ssh server1
```

Daarna herhalen voor:

```powershell
vagrant ssh server2
```

```powershell
vagrant ssh server3
```

Gebruik per server het Vagrant-beheerdersaccount. Start binnen iedere server:

```cmd
powershell
```

Voer op iedere server uit:

```powershell
& {
    $ErrorActionPreference = "Stop"

    hostname
    whoami

    $Profiles = @(
        Get-NetFirewallProfile -PolicyStore ActiveStore
    )

    $Profiles |
        Select-Object Name, Enabled,
            DefaultInboundAction, DefaultOutboundAction |
        Format-Table -AutoSize

    $Unexpected = @(
        $Profiles |
            Where-Object {
                $_.Enabled.ToString() -ne "True" -or
                $_.DefaultInboundAction.ToString() -ne "Block" -or
                $_.DefaultOutboundAction.ToString() -ne "Allow"
            }
    )

    if ($Unexpected.Count -gt 0) {
        throw "Firewallprofielen wijken af van het labontwerp."
    }

    Write-Output "PASS: SSH-sessie werkt en alle firewallprofielen voldoen."
}
```

Verlaat iedere sessie met tweemaal `exit` voordat je de volgende SSH-verbinding opent.

Controleer ook SSH naar CLIENT vanaf de host:

```powershell
vagrant ssh client
```

Binnen CLIENT:

```cmd
hostname
whoami
```

Een geslaagde sessie bevestigt de bedoelde SSH-toegangsroute vanaf de host. Ze bewijst niet automatisch toegang via een andere netwerkroute.

#### 6. Automatische zone transfer als aanvullend bewijs

Gebruik het geslaagde resultaat van T17.

Indien opnieuw nodig:

- Machine: server1.
- Account: `WS26-JD\Administrator`.
- Uitvoering: het volledige T17-blok voor aanmaken, automatische overname, verwijderen en automatische verwijdering van het eigen tijdelijke CNAME-record.

Forceer geen handmatige zone transfer om deze automatische-overnamecontrole te laten slagen.

#### Acceptatiecriteria

- Alle vier bedoelde TCP-verbindingen slagen.
- Beide DNS-servers beantwoorden de intranetquery correct.
- Intranet geeft HTTP `200` met Hello World.
- Extern DHCP-beheer via de RSAT-tools werkt met het domeinbeheerdersaccount.
- CLIENT heeft een echte, overeenkomende DHCP-lease op server3.
- Web Enrollment werkt vanaf CLIENT volgens T26.
- Automatische zone transfer is bevestigd volgens T17.
- SSH vanaf de host werkt naar alle vier machines.
- De serverfirewalls blijven ingeschakeld met inkomend `Block` en uitgaand `Allow`.
- De controles vereisen geen firewalluitschakeling.

Status: SUCCESVOL

### T35 — Herhaalbaarheid

Voer alleen een gerichte, vooraf beoordeelde provisioner opnieuw uit.

Voorbeeld: de eerder gecontroleerde templateprovisioner.

Vergelijk vóór en na:

- Aantal en inhoud van beheerde ACL-regels.
- Eigenaar.
- Aantal GPOs en links.
- Certificaten en HTTPS-bindings wanneer die onderdelen getest worden.
- Aantal beheerde firewallregels.

Acceptatiecriteria:

- Geen dubbele objecten of onbedoelde rechten.
- Bestaande certificaten worden hergebruikt wanneer geschikt.
- Geen nieuwe reboots door het ongericht opnieuw uitvoeren van join- of promotieprovisioners.

Een succesvolle herhaling van één provisioner bewijst niet dat het hele
project volledig idempotent is.

Status: NIET GETEST

## 15. Resultatenregister

Vul dit na uitvoering in.

| Test | Onderdeel | Resultaat | Bewijs / opmerking |
|---|---|---|---|
| T02 | PowerShell-syntaxis | SUCCESVOL | |
| T03 | Boxes en VirtualBox-netwerk | SUCCESVOL | |
| T04 | Volledige uitrol | SUCCESVOL | |
| T05 | SSH met firewall | SUCCESVOL | |
| T06 | OS en Server Core | SUCCESVOL | |
| T07 | Statische serveradressen | SUCCESVOL | |
| T08 | DNS-clientinstellingen | SUCCESVOL | |
| T09 | Domeinlidmaatschap | SUCCESVOL | |
| T10 | Functional levels en enige DC | SUCCESVOL | |
| T11 | OUs en computerobjecten | SUCCESVOL | |
| T12 | Gebruikers en rechten | SUCCESVOL | |
| T13 | DNS-rollen en zones | SUCCESVOL | |
| T14 | Exacte A- en PTR-records | SUCCESVOL | |
| T15 | Beide DNS-servers in zones | SUCCESVOL | |
| T16 | Geen ongewenste registraties | SUCCESVOL | |
| T17 | Automatische zone transfer | SUCCESVOL | |
| T18 | DHCP-rol en scope | SUCCESVOL | |
| T19 | DHCP-opties en bindings | SUCCESVOL | |
| T20 | Echte clientlease | SUCCESVOL | |
| T21 | CA en Web Enrollment-rollen | SUCCESVOL | |
| T22 | Actueel rootcertificaat | SUCCESVOL | |
| T23 | CA-trust-GPO | SUCCESVOL | |
| T24 | Trust op alle vier machines | SUCCESVOL | |
| T25 | HTTPS-certificaat en binding | SUCCESVOL | |
| T26 | Web Enrollment vanaf client | SUCCESVOL | |
| T27 | IIS lokaal | SUCCESVOL | |
| T28 | Intranet vanaf client | SUCCESVOL | |
| T29 | RSAT-installatie | SUCCESVOL | |
| T31 | Firewallprofielen | SUCCESVOL | |
| T32 | Minimale inkomende regels | SUCCESVOL | |
| T33 | Diensten met actieve firewall | SUCCESVOL | |
| T34 | Tijdelijke hulpmiddelen | SUCCESVOL | |
| T35 | Herhaalbaarheid | NIET GETEST | |