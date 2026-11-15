# Deploymentguide en portfolio — Windows Server II, deel 1

Opleidingsonderdeel: Windows Server II (EP1 — 2026-2027)  
Hogeschool: HOGENT — Toegepaste Informatica  
Auteur: Nicholas Stanescu  
Domein: `WS26-JD.hogent`  
Intern netwerk: Host-Only `192.168.26.0/24`

## Inhoudsopgave

1. Handleiding voor de uitrol  
   1.1 Vereisten en voorbereiding · 1.2 Netwerk en machines · 1.3 Accounts · 1.4 Uitrol · 1.5 Controles
2. Projectstatus  
   2.1 Afgewerkt · 2.2 Openstaand · 2.3 Problemen en oplossingen
3. Reflectie  
   3.1 Geleerd · 3.2 Volgende aanpak · 3.3 Tijdsbesteding

## 1. Handleiding voor de uitrol

### 1.1 Vereisten en voorbereiding

| Onderdeel | Vereiste |
|---|---|
| RAM | Minstens 16 GB; bij voorkeur 24–32 GB voor vier gelijktijdige VM’s |
| CPU | Minstens vier fysieke cores en acht threads; VT-x/AMD-V ingeschakeld in BIOS/UEFI |
| Opslag | Minstens 50 GB vrij, bij voorkeur SSD |
| Hostbesturingssysteem | Windows 10/11, macOS of Linux |
| VirtualBox | 7.2.x, bijvoorbeeld 7.2.18 |
| Automatisatie | HashiCorp Vagrant |
| Shell | PowerShell 5.1 of 7+, met administratorrechten op de host |

Vagrant kan op Windows geïnstalleerd worden met:

```powershell
winget install Hashicorp.Vagrant
```

De Vagrantfile gebruikt deze vastgepinde boxen:

| Box | Versie |
|---|---|
| `gusztavvargadr/windows-server-2025-standard-core` | `2607.0.0` |
| `gusztavvargadr/windows-11-25h2-enterprise` | `2607.1.0` |

Schakel de VirtualBox-DHCP-server uit op het gebruikte Host-Only-netwerk. Server3 verzorgt daar DHCP.

### 1.2 Netwerk en machines

Elke VM heeft een NAT-interface voor internet en Vagrant-beheer via WinRM/SSH, en een Host-Only-interface voor interne communicatie. De interne interface heeft geen rechtstreekse internetverbinding.

```text
        NAT per VM: internet en WinRM/SSH-beheer
             |          |          |          |
          server1    server2    server3     client
NAT:      10.0.2.15   10.0.2.15   10.0.2.15  10.0.2.15
Intern:   .26.10      .26.20      .26.30     DHCP (.100+)
             |          |          |          |
             +----------+----------+----------+
                 Host-Only 192.168.26.0/24
                  Geen interne NAT-uplink
```

| VM | Besturingssysteem | Intern adres | Rollen en AD-locatie |
|---|---|---|---|
| server1 | Windows Server 2025 Core | `192.168.26.10/24` | Domeincontroller, primaire DNS en IIS voor `intranet.WS26-JD.hogent` |
| server2 | Windows Server 2025 Core | `192.168.26.20/24` | Secundaire DNS; domeinlid in `OU=Servers` |
| server3 | Windows Server 2025 Core | `192.168.26.30/24` | Enterprise Root CA `WS26-JD-Root-CA`, Web Enrollment `/CertSrv` en DHCP; domeinlid in `OU=Servers` |
| client | Windows 11 Enterprise | DHCP | RSAT-beheer; domeinlid in `OU=Clients` |

### 1.3 Gebruikers en wachtwoorden

De UPN’s in onderstaande tabel gebruiken het achtervoegsel `@WS26-JD.hogent`.

| Gebruiker | Account of UPN | Rol en locatie | Wachtwoord |
|---|---|---|---|
| Administrator | `WS26-JD\Administrator` | Ingebouwde Domain Admin en Enterprise Admin; `CN=Users` | `JouwSterkWachtwoord123!` |
| j.doe.adm | `j.doe.adm@WS26-JD.hogent` | Domain Admin; `OU=Beheer` | `W@chtwoord2026!` |
| a.smit.adm | `a.smit.adm@WS26-JD.hogent` | Domain Admin; `OU=Beheer` | `W@chtwoord2026!` |
| p.jansen | `p.jansen@WS26-JD.hogent` | Gewone domeingebruiker; `OU=Medewerkers` | `W@chtwoord2026!` |
| m.peeters | `m.peeters@WS26-JD.hogent` | Gewone domeingebruiker; `OU=Medewerkers` | `W@chtwoord2026!` |
| vagrant | `CLIENT\vagrant` | Lokaal Vagrant-beheer en provisioning; niet in AD | Wachtwoord uit de Vagrant-box |

Het DSRM-herstelwachtwoord is `JouwSterkWachtwoord123!` en wordt ingesteld bij de promotie van server1.

### 1.4 De omgeving uitrollen

#### Project ophalen en starten

Voer op de host uit:

```powershell
git clone https://github.com/nicostan15/Windows-Server-II-portofolio WS2-Portfolio
cd WS2-Portfolio
```

Controleer of `Vagrantfile` en `scripts/` aanwezig zijn. Start daarna de uitrol:

```powershell
vagrant up
```

Vagrant maakt de vier VM’s aan en voert de configuratiescripts uit.

#### Automatische configuratie per machine

| Machine | Configuratie |
|---|---|
| server1 | Statisch adres `192.168.26.10/24`; forest en domein `WS26-JD.hogent` met Windows Server 2025-functionaliteitsniveaus; primaire domeinzone, reversezone `26.168.192.in-addr.arpa` en aparte `_msdcs`-zone; vier OU’s en vier gebruikers; IIS-intranet; firewallregels voor diensten en beheer. |
| server2 | Statisch adres `192.168.26.20/24`; domeinjoin in `OU=Servers,DC=WS26-JD,DC=hogent`; DNS-rol en secundaire zones met automatische overdracht vanaf server1. |
| server3 | Statisch adres `192.168.26.30/24`; domeinjoin in de Servers-OU; Enterprise Root CA `WS26-JD-Root-CA`; Web Enrollment `/CertSrv`; publicatie van het rootcertificaat via `certutil -dspublish`; DHCP-scope `.100–.200`, exclusion `.151–.200`, opties 6 en 15 en AD-autorisatie. |
| client | Intern adres via DHCP van server3; RSAT-installatie; clientfirewall; domeinjoin in `OU=Clients,DC=WS26-JD,DC=hogent`; herstart. |

De HTTPS-certificaataanvraag, HTTPS-binding en HTTP-redirect op server3 volgen tijdens de CA-eindfase.

#### CA-eindfase met `lab-finalize`

Deze laatste clientprovisioner voert de volgende stappen uit:

1. Controleren of server1 en server3 draaien en via Vagrant bereikbaar zijn.
2. De WebServer-template op server1 configureren.
3. HTTPS voor Web Enrollment op server3 configureren.
4. De GPO `WS26 - Vertrouw Root CA` configureren en koppelen.
5. Rootvertrouwen en Web Enrollment op server1 controleren.
6. Het actuele publieke CA-certificaat van server3 als referentiebestand naar de client kopiëren.
7. `client-verify-ca` uitvoeren met `-ExpectedCertificatePath`.

Het kopiëren van het referentiebestand importeert geen certificaat in de vertrouwde opslag.

### 1.5 De werking controleren

Voer alle `vagrant`-opdrachten op de host uit, vanuit de projectmap. Start na een SSH-aanmelding zo nodig PowerShell met `powershell`. Sluit daarna eerst PowerShell en vervolgens de SSH-sessie met telkens `exit`. Open de volgende verbinding pas wanneer je terug op de host bent.

#### A. Active Directory — server1

Open vanaf de host:

```powershell
vagrant ssh server1
```

Voer binnen server1 uit:

```powershell
powershell
Get-ADDomain | Select-Object Name, DomainMode
Get-ADForest | Select-Object Name, ForestMode
Get-ADOrganizationalUnit -Filter * | Select-Object Name, DistinguishedName
Get-ADUser -Filter * | Select-Object SamAccountName, UserPrincipalName
```

Verwacht: `Windows2025Domain`, `Windows2025Forest` en de vier eigen OU’s en gebruikers.

#### B. Secundaire DNS — server2

Open vanaf de host:

```powershell
vagrant ssh server2
```

Voer binnen server2 uit:

```powershell
powershell
Get-DnsServerZone | Where-Object ZoneType -eq "Secondary"
Resolve-DnsName intranet.WS26-JD.hogent -Server 192.168.26.20
```

Verwacht: `WS26-JD.hogent`, `_msdcs.WS26-JD.hogent` en `26.168.192.in-addr.arpa` als `Secondary`. Het intranet resolveert naar `192.168.26.10`.

#### C. DHCP en AD-autorisatie — server3

Open vanaf de host:

```powershell
vagrant ssh server3
```

Voer binnen server3 uit:

```powershell
powershell
Get-DhcpServerv4Scope -ScopeId 192.168.26.0
Get-DhcpServerv4OptionValue -ScopeId 192.168.26.0
```

Verwacht: een actieve scope van `.100` tot en met `.200`, optie 6 met `192.168.26.10` en `192.168.26.20`, en optie 15 met `WS26-JD.hogent`.

Voor de AD-autorisatiecontrole is het domein-Administratoraccount nodig. Sluit de sessie en controleer op de host de SSH-poort:

```powershell
vagrant ssh-config server3
```

Vervang `<SSH-poort>` door de waarde achter `Port`:

```powershell
ssh -p <SSH-poort> -l 'WS26-JD\Administrator' -o PreferredAuthentications=password -o PasswordAuthentication=yes -o PubkeyAuthentication=no 127.0.0.1
```

Voer het wachtwoord in bij de prompt. Voer daarna op server3 uit:

```powershell
powershell
whoami
Get-DhcpServerInDC
```

Verwacht: `ws26-jd\administrator` als identiteit en `server3.WS26-JD.hogent` met adres `192.168.26.30` in de autorisatielijst. Sluit de sessie voordat je verdergaat op de host.

#### D. Web Enrollment en HTTP-redirect

Voer op de host uit:

```powershell
vagrant provision server1 --provision-with server1-verify-web-enrollment
```

Deze controle draait op server1 en test de HTTP-ingang, redirect en HTTPS-pagina.

#### E. CA-eindfase en clientcontrole

Met alle VM’s ingeschakeld voer je op de host uit:

```powershell
vagrant provision client --provision-with lab-finalize
```

Dit voert de CA-stappen opnieuw uit en haalt het actuele publieke CA-certificaat op als referentie voor de clientcontrole. De verwachte eindmelding is:

```text
Automatische CA-naverwerking en clientcontrole geslaagd.
```

#### F. SSH met ingeschakelde firewall

Voer onderstaande opdrachten afzonderlijk op de host uit. Sluit elke verbinding voordat je de volgende opent:

```powershell
vagrant ssh server1
vagrant ssh server2
vagrant ssh server3
vagrant ssh client
```

Alle vier de VM’s moeten bereikbaar zijn. De firewallprofielen en standaardacties worden afzonderlijk met de firewallcontroles bevestigd.

## 2. Projectstatus

### 2.1 Afgewerkte onderdelen

De basisdiensten zijn geïmplementeerd. Eén `vagrant up` rolt de omgeving uit, inclusief CA-eindfase en clientcontrole.

| Onderdeel | Afgewerkt |
|---|---|
| Netwerk | Vaste interne serveradressen; VirtualBox-DHCP uit op Host-Only |
| Active Directory | `WS26-JD.hogent`; forest- en domeinfunctionaliteitsniveau Windows Server 2025 |
| OU’s en gebruikers | Vier eigen OU’s, twee beheeraccounts en twee gewone gebruikers |
| DNS | Primaire en secundaire forward- en reversezones; zoneoverdracht via NOTIFY getest |
| DHCP | Scope, exclusion, DNS-opties, interne binding en AD-autorisatie |
| CA en GPO | Enterprise Root CA en GPO voor het verdelen van rootvertrouwen |
| Web Enrollment | Eigen HTTPS-certificaat op poort 443 en HTTP-redirect op poort 80 |
| IIS | Hello World via `http://intranet.WS26-JD.hogent` |
| Client | Automatische RSAT-installatie en domeinjoin in Clients-OU |
| Firewall | Firewall actief op alle VM’s; inbound Block, outbound Allow; rol- en SSH/WinRM-uitzonderingen |
| Automatisering | `lab-finalize` voert de CA-stappen en clientcontrole uit |

### 2.2 Openstaande punten

De SQL Failover Cluster-configuratie tussen server2 en server3 en de IIS HTTPS-uitbreiding volgen in deel 2.

### 2.3 Problemen en oplossingen

| Probleem | Oorzaak of vaststelling | Oplossing |
|---|---|---|
| WinRM na domeinpromotie | Authenticatie via de doorgestuurde Vagrant-poort werkte niet meer met de gebruikte instellingen. | `:plaintext`, `basic_auth_only = true` en hogere `retry_limit` en `retry_delay`. |
| Functionaliteitsniveau 2016 | `Install-ADDSForest` gebruikte `WinThreshold`. | `-ForestMode` en `-DomainMode` aangepast naar `"Win2025"`. |
| HTTP 403.4 op `/CertSrv` | De pagina vereiste HTTPS. | Aparte HTTP-site met 302-redirect naar `https://server3.WS26-JD.hogent/certsrv/Default.asp`. |
| Publicatie rootcertificaat faalde | De oorspronkelijke geplande taak werkte niet zoals verwacht. | `certutil -dspublish` via `cmd.exe`, met logging naar `C:\ProgramData\WS2-PublishRootCA.log`. |
| WinRM geblokkeerd door firewall | Servicefilter `WinRM` liet het doorgestuurde NAT-verkeer niet door. | Filter van `WS2-Managed-WinRM-NAT` naar `Any`; bron `10.0.2.2` en poort `5985` behouden. |
| Herhaalde firewallprovisioning faalde | `DisplayName` en `Group` waren onjuist gecombineerd als selectie- en updateparameters. | In `Set-LabAllowRule` updateparameters kopiëren, beide velden verwijderen en `NewDisplayName` gebruiken. |
| Client ontving trust-GPO niet | De client was nog geen domeinlid. | Client-domeinjoin in de Vagrantfile vóór de CA-verificatie geplaatst. |

## 3. Conclusie en reflectie

### 3.1 Wat heb ik geleerd?

De volgorde van de configuratie bleek belangrijk. Netwerk en DNS moeten werken vóór de domeinjoin. De CA moet beschikbaar zijn vóór een certificaataanvraag. Rootvertrouwen kan pas gecontroleerd worden wanneer de GPO klaarstaat en de client domeinlid is.

Ik houd nu meer rekening met het opnieuw uitvoeren van scripts. Waar mogelijk controleren ze eerst of een rol, gebruiker, zone of certificaat bestaat. Zo blijven bestaande instellingen behouden en ontstaan geen onnodige dubbele objecten.

Door de Vagrant- en firewallproblemen heb ik gewerkt met WinRM-listeners, NAT-verkeer, RPC-poorten en servicefilters. Een draaiende service of bereikbare TCP-poort bleek niet voldoende om te besluiten dat een beheerverbinding werkt.

Daarnaast heb ik ervaring opgedaan met een Enterprise Root CA, certificaatpublicatie in Active Directory en rootvertrouwen via GPO.

### 3.2 Wat zou ik anders aanpakken?

Ik zou configuratie en controles vanaf het begin duidelijker scheiden. Met aparte verificatiescripts kan ik de werking controleren zonder de configuratie opnieuw toe te passen.

Ook zou ik de firewallopbouw vroeger vastleggen. Regels kunnen bijvoorbeeld bij hun rolscript staan: DNS-regels bij DNS en HTTP-regels bij IIS. Zo is sneller duidelijk waarvoor elke regel dient.

### 3.3 Wat heeft de meeste tijd gekost?

1. WinRM na de domeinpromotie. Het opsporen van de verloren Vagrant-verbinding kostte veel tijd. Met `:plaintext` en Basic-authenticatie werkte de verbinding in deze labomgeving opnieuw.
2. HTTPS en de redirect op server3. De certificaataanvraag onder domeincredentials, geplande taak, HTTPS-binding, authenticatie en IIS SSL-instellingen moesten op elkaar aansluiten. Hiervoor waren meerdere tests nodig.
3. Firewalldiagnose op Server Core. Zonder GUI verliep dit via PowerShell, SSH en `netsh advfirewall`. Ik vergeleek regels, actieve verbindingen en loggegevens om te vinden waar verkeer werd geblokkeerd.