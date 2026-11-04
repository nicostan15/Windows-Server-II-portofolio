# Deployment Guide & Portfolio Deel 1 — Windows Server II

**Opleidingsonderdeel:** Windows Server II (EP1 — 2026-2027)  
**Hogeschool:** HOGENT — Bachelor Toegepaste Informatica  
**Auteur:** [Jouw Naam] ([Klasgroep])  
**Domeinnaam:** `WS26-JD.hogent`  
**Netwerk:** Host-Only `192.168.26.0/24`  

---

## Inhoudsopgave

1. [Deel 1: Handleiding voor Uitrol (Deployment Guide)](#1-deel-1-handleiding-voor-uitrol-deployment-guide)
   - [1.1 Systeemvereisten & Voorbereiding](#11-systeemvereisten--voorbereiding)
   - [1.2 Netwerk- en Architectuuroverzicht](#12-netwerk--en-architectuuroverzicht)
   - [1.3 Overzicht van Gebruikers & Wachtwoorden](#13-overzicht-van-gebruikers--wachtwoorden)
   - [1.4 Stap-voor-stap Uitrolhandleiding (Dummyproof)](#14-stap-voor-stap-uitrolhandleiding-dummyproof)
   - [1.5 Verificatie & Acceptatietesten](#15-verificatie--acceptatietesten)
2. [Deel 2: Huidige Status van het Project](#2-deel-2-huidige-status-van-het-project)
   - [2.1 Wat is afgewerkt](#21-wat-is-afgewerkt)
   - [2.2 Wat is nog niet af / Aandachtspunten](#22-wat-is-nog-niet-af--aandachtspunten)
   - [2.3 Technische Problemen & Oplossingen](#23-technische-problemen--oplossingen)
3. [Deel 3: Conclusie & Reflectie](#3-deel-3-conclusie--reflectie)
   - [3.1 Wat heb je geleerd?](#31-wat-heb-je-geleerd)
   - [3.2 Wat zou je in de toekomst anders doen?](#32-wat-zou-je-in-de-toekomst-anders-doen)
   - [3.3 Aan welke zaken is veel tijd verloren gegaan?](#33-aan-welke-zaken-is-veel-tijd-verloren-gegaan)

---

## 1. Deel 1: Handleiding voor Uitrol (Deployment Guide)

### 1.1 Systeemvereisten & Voorbereiding

Om deze geautomatiseerde Windows Server 2025 & Windows 11 labomgeving correct uit te rollen op je lokaal toestel, moet de hostcomputer aan onderstaande voorwaarden voldoen:

* **Hardware:**
  * **RAM:** Minstens 16 GB RAM (24 GB tot 32 GB wordt sterk aanbevolen).
  * **CPU:** Minstens 4 fysieke cores / 8 threads met virtualisatie-ondersteuning (VT-x / AMD-V) ingeschakeld in de BIOS/UEFI.
  * **Opslag:** Minstens 50 GB vrije schijfruimte (bij voorkeur SSD).
* **Software:**
  * **Besturingssysteem:** Windows 10/11, macOS of Linux.
  * **Hypervisor:** VirtualBox **7.2.x** (bv. VirtualBox 7.2.18).
  * **Automatisatie:** HashiCorp Vagrant (installatie via winget op Windows: `winget install Hashicorp.Vagrant`).
  * **Shell:** PowerShell 5.1 of PowerShell 7+ met Administrator-rechten op de host.
* **Vagrant Boxes (Vastgepind):**
  * Windows Server 2025 Core: `gusztavvargadr/windows-server-2025-standard-core` (versie `2607.0.0`).
  * Windows 11 Enterprise: `gusztavvargadr/windows-11-25h2-enterprise` (versie `2607.1.0`).

> **Belangrijk:** De VirtualBox-interne DHCP-server op de Host-Only netwerkadapter moet **uitgeschakeld** zijn. De DHCP-dienst voor het netwerk wordt volledig verzorgd door **server3**!

---

### 1.2 Netwerk- en Architectuuroverzicht

Het labnetwerk bestaat uit vier virtuele machines verdeeld over twee netwerkinterfaces per VM:
1. **NAT-interface (VirtualBox Engine):** Biedt internettoegang en WinRM/SSH-beheer voor Vagrant.
2. **Host-Only interface (`192.168.26.0/24`):** Interne communicatie tussen de servers en clients zonder directe internet-uplink.

```
                    +----------------------------------+
                    |  VirtualBox NAT Engine (Internet) |
                    +----------------------------------+
                                     |
           +-------------------------+-------------------------+
           | 10.0.2.15               | 10.0.2.15               | 10.0.2.15               | 10.0.2.15
     +-----------+             +-----------+             +-----------+             +-----------+
     |  server1  |             |  server2  |             |  server3  |             |   client  |
     | WS2025 C. |             | WS2025 C. |             | WS2025 C. |             |  Win11 E. |
     +-----------+             +-----------+             +-----------+             +-----------+
           | 192.168.26.10           | 192.168.26.20           | 192.168.26.30           | DHCP (.100+)
           +-------------------------+-------------------------+-------------------------+
                                     |
                       +----------------------------+
                       | Host-Only Network (No NAT) |
                       |      192.168.26.0/24       |
                       +----------------------------+
```

#### Matrix Virtuele Machines & Rollen

| VM / Hostnaam | Besturingssysteem | IP (Host-Only) | Active Directory & Netwerkrollen |
|---|---|---|---|
| **server1** | Windows Server 2025 Core | `192.168.26.10/24` | Primary Domain Controller (`WS26-JD.hogent`), Primaire DNS-server, IIS Webserver (`intranet.WS26-JD.hogent`) |
| **server2** | Windows Server 2025 Core | `192.168.26.20/24` | Secundaire DNS-server (Domain-joined in `OU=Servers`) |
| **server3** | Windows Server 2025 Core | `192.168.26.30/24` | Enterprise Root CA (`WS26-JD-Root-CA`), Web Enrollment Service (`/CertSrv`), DHCP Server (Domain-joined in `OU=Servers`) |
| **client** | Windows 11 Enterprise | Dynamisch (DHCP) | Beheersstation met RSAT Tools, Domeinlid (`OU=Clients`) |

---

### 1.3 Overzicht van Gebruikers & Wachtwoorden

Voor het beheer van het Active Directory domein `WS26-JD.hogent` zijn de volgende accounts en wachtwoorden geconfigureerd:

| Gebruikersnaam | UPN / Account | Active Directory Rol / Groep | OU Locatie | Wachtwoord |
|---|---|---|---|---|
| **Administrator** | `WS26-JD\Administrator` | Ingebouwde Domain Admin & Enterprise Admin | `CN=Users` | `JouwSterkWachtwoord123!` |
| **j.doe.adm** | `j.doe.adm@WS26-JD.hogent` | Domain Admin | `OU=Beheer` | `W@chtwoord2026!` |
| **a.smit.adm** | `a.smit.adm@WS26-JD.hogent` | Domain Admin | `OU=Beheer` | `W@chtwoord2026!` |
| **p.jansen** | `p.jansen@WS26-JD.hogent` | Domain User (Gewone gebruiker) | `OU=Medewerkers` | `W@chtwoord2026!` |
| **m.peeters** | `m.peeters@WS26-JD.hogent` | Domain User (Gewone gebruiker) | `OU=Medewerkers` | `W@chtwoord2026!` |
| **vagrant** | `WS26-JD\vagrant` | Domain Admin (Geautomatiseerd beheer) | `CN=Users` | *Standaard Vagrant wachtwoord* (`vagrant`) |

> **DSRM Wachtwoord (Active Directory Restore Mode):** `JouwSterkWachtwoord123!` (geconfigureerd bij DC-promotie op server1).

---

### 1.4 Stap-voor-stap Uitrolhandleiding (Dummyproof)

Met deze stappen kan elke eerstejaarsstudent Toegepaste Informatica de gehele omgeving met één enkel commando uitrollen.

#### Stap 1: Repository binnenhalen en voorbereiden
1. Open PowerShell of je terminal en navigeer naar de gewenste map:
   ```powershell
   git clone <repository-url> WS2-Portfolio
   cd WS2-Portfolio
   ```
2. Controleer of de map de `Vagrantfile` en de map `scripts/` bevat.

#### Stap 2: De Omgeving Uitrollen via Vagrant
Voer in de hoofdmap het volgende commando uit:

```powershell
vagrant up
```

#### Wat gebeurt er automatisch achter de schermen?

1. **Uitrol server1:**
   * Statische Host-Only IP-configuratie (`192.168.26.10/24`).
   * Promotie tot Primary Domain Controller voor forest `WS26-JD.hogent` met functional level **Windows Server 2025**.
   * Automatische installatie en configuratie van de **Primaire DNS-server** (Forward zone `WS26-JD.hogent`, Reverse zone `26.168.192.in-addr.arpa` en `_msdcs`).
   * Aanmaken van de OU-structuur (`Beheer`, `Medewerkers`, `Servers`, `Clients`) en de 4 vereiste gebruikers.
   * Installatie van IIS en uitrol van de intranet-website (`http://intranet.WS26-JD.hogent`).
   * Aanpassing van de Windows Firewall (alleen noodzakelijke poorten open op de Host-Only interface).

2. **Uitrol server2:**
   * Statische Host-Only IP-configuratie (`192.168.26.20/24`).
   * Automatische domeinjoin in `OU=Servers,DC=WS26-JD,DC=hogent`.
   * Installatie van de DNS-rol en configuratie van **Secundaire DNS-zones** met automatische zone transfers vanaf server1.

3. **Uitrol server3:**
   * Statische Host-Only IP-configuratie (`192.168.26.30/24`).
   * Automatische domeinjoin in `OU=Servers,DC=WS26-JD,DC=hogent`.
   * Installatie van Active Directory Certificate Services (AD CS) als **Enterprise Root CA** (`WS26-JD-Root-CA`).
   * Installatie van **CA Web Enrollment** (`/CertSrv`) inclusief HTTPS-binding (poort 443) met een door de eigen CA uitgegeven certificaat en automatische HTTP (poort 80) **302 Redirect**.
   * Publicatie van het CA Root-certificaat in Active Directory (`certutil -dspublish`).
   * Installatie van de **DHCP-serverrol** met een actieve scope `192.168.26.100`–`192.168.26.200` (exclusion `192.168.26.151`–`192.168.26.200`), instelling van DHCP-opties (Option 6 DNS, Option 15 Domain Name) en autorisatie in Active Directory.

4. **Geautomatiseerde Triggers & CA Trust GPO:**
   * Na het starten van server3 voert Vagrant automatisch een trigger uit op server1:
     * Geef de WebServer-template de juiste DACL-rechten.
     * Maak de Group Policy Object **`WS26 - Vertrouw Root CA`** aan en koppel deze aan de domeinroot.
     * Automatische verificatie van Web Enrollment en CA-trust via PowerShell.

5. **Uitrol client (Windows 11):**
   * Verkrijgt een dynamisch IP-adres via DHCP van server3.
   * Automatische installatie van de benodigde **RSAT Tools** (AD DS, DNS, DHCP, GPMC).
   * Automatische domeinjoin in `OU=Clients,DC=WS26-JD,DC=hogent`.
   * Vernieuwen van het Group Policy beleid (`gpupdate /force`), waarna het CA Root-certificaat automatisch wordt toegevoegd aan de `Trusted Root Certification Authorities` store.
   * Verificatie van toegang tot het intranet.

---

### 1.5 Verificatie & Acceptatietesten

Na de uitrol kun je de werking van alle diensten eenvoudig verifiëren via onderstaande PowerShell-commando's.

#### A. Active Directory & Functional Levels (server1)
```powershell
vagrant ssh server1
powershell

Get-ADDomain | Select-Object Name, DomainMode
Get-ADForest | Select-Object Name, ForestMode
Get-ADOrganizationalUnit -Filter * | Select-Object Name, DistinguishedName
Get-ADUser -Filter * | Select-Object SamAccountName, UserPrincipalName
```
* **Verwacht resultaat:** `DomainMode` en `ForestMode` staan beide op `Windows2025Domain` / `Windows2025Forest`. De 4 OU's en gebruikers zijn zichtbaar.

#### B. DNS Replicatie & Zone Transfer (server2)
```powershell
vagrant ssh server2
powershell

Get-DnsServerZone | Where-Object ZoneType -eq "Secondary"
Resolve-DnsName intranet.WS26-JD.hogent -Server 192.168.26.20
```
* **Verwacht resultaat:** De DnsZones (`WS26-JD.hogent`, `_msdcs.WS26-JD.hogent` en `26.168.192.in-addr.arpa`) zijn geladen als `Secondary`. `intranet.WS26-JD.hogent` resolveert naar `192.168.26.10`.

#### C. DHCP Scope & Autorisatie (server3)
```powershell
vagrant ssh server3
powershell

Get-DhcpServerv4Scope -ScopeId 192.168.26.0
Get-DhcpServerv4OptionValue -ScopeId 192.168.26.0
Get-DhcpServerInDC
```
* **Verwacht resultaat:** Scope `192.168.26.100`–`200` is `Active`. DNS-servers staan op `192.168.26.10` en `192.168.26.20`. Server3 is vermeld als geautoriseerde DHCP-server.

#### D. CA Web Enrollment & Redirect (server1 of client)
```powershell
vagrant provision server1 --provision-with server1-verify-web-enrollment
```
* **Verwacht resultaat:**
  * HTTP-ingang `http://server3.WS26-JD.hogent/CertSrv/` retourneert status `302 Found`.
  * Redirect verwijst naar `https://server3.WS26-JD.hogent/certsrv/Default.asp`.
  * HTTPS-pagina retourneert HTTP status `200 OK` met titel `Microsoft Active Directory Certificate Services`.

#### E. Client CA-Trust & Intranet (client)
```powershell
vagrant provision client --provision-with client-verify-ca
```
* **Verwacht resultaat:** `Root-CA aanwezig:` toont het certificaat met thumbprint in `Cert:\LocalMachine\Root`. `Intranet is bereikbaar: HTTP 200.`

#### F. SSH-toegang met actieve Firewall
```powershell
vagrant ssh server1
vagrant ssh server2
vagrant ssh server3
vagrant ssh client
```
* **Verwacht resultaat:** Alle VM's zijn via SSH bereikbaar terwijl de Windows Defender Firewall ingeschakeld is met `DefaultInboundAction = Block`.

---

## 2. Deel 2: Huidige Status van het Project

### 2.1 Wat is afgewerkt

Alle verplichte en optionele onderdelen van **Deel 1 (Automatisatie basisdiensten)** zijn 100% geïmplementeerd en geautomatiseerd:

* [x] **Netwerkinrichting:** Statische IP's op Host-Only voor alle servers (`.10`, `.20`, `.30`), VirtualBox DHCP uitgeschakeld.
* [x] **Active Directory DS:** `WS26-JD.hogent` geconfigureerd met **Windows Server 2025** Forest en Domain functional level.
* [x] **OU & Gebruikersbeheer:** 4 OU's aangemaakt (`Beheer`, `Medewerkers`, `Servers`, `Clients`), 4 gebruikers aangemaakt (2x Domain Admin, 2x Domain User).
* [x] **DNS (Primary & Secondary):** Primary DNS op server1, Secondary DNS op server2. Forward & Reverse zones geconfigureerd. Zone transfers getest en werkend via NOTIFY.
* [x] **DHCP Server:** Actieve DHCP-scope op server3 (`.100` tot `.200`, exclusion `.151` tot `.200`), DNS-opties ingesteld, gebonden aan Host-Only interface en geautoriseerd in Active Directory.
* [x] **Certification Authority & GPO:** Enterprise Root CA op server3. Automatische uitrol van de GPO `WS26 - Vertrouw Root CA` op het domein, waardoor alle domeinleden het rootcertificaat vertrouwen.
* [x] **Web Enrollment:** Geïnstalleerd op server3, voorzien van HTTPS (poort 443) via een eigen webservercertificaat, en een automatische HTTP (poort 80) 302-redirect.
* [x] **IIS Intranet:** Geïnstalleerd op server1, bereikbaar via `http://intranet.WS26-JD.hogent` met een statische HTML "Hello World"-pagina.
* [x] **RSAT Tools & Client Domain Join:** RSAT automatisch geïnstalleerd op de Windows 11 client, client toegevoegd aan `OU=Clients`.
* [x] **Beveiliging & Firewall:** Windows Firewall ingeschakeld op alle VM's (`DefaultInboundAction = Block`, `DefaultOutboundAction = Allow`). Enkel noodzakelijke rolgebonden poorten en SSH/WinRM-beheerpoorten zijn geopend.
* [x] **Volledige Automatisering:** De complete omgeving bouwt op via één enkel `vagrant up` commando inclusief geautomatiseerde triggers voor CA-afhankelijke vervolgstappen.

---

### 2.2 Wat is nog niet af / Aandachtspunten

* **Definitieve end-to-end schone herbouw:** Een allerlaatste validatie via `vagrant destroy -f` gevolg door `vagrant up` moet kort voor het definitief inleveren nog eenmaal integraal worden doorlopen om te garanderen dat de timing en afhankelijkheden op elk hostsysteem exact kloppen.
* **Voorbereiding op Deel 2:** De SQL Failover Cluster configuratie tussen server2 en server3 (inclusief IIS HTTPS-uitbreiding voor Deel 2) volgt in de volgende fase van het portfolio.

---

### 2.3 Technische Problemen & Oplossingen

Tijdens het ontwikkelproces zijn een aantal complexe uitdagingen aangepakt en opgelost:

| Probleem / Symptoom | Oorspronkelijke Oorzaak | Toegepaste Oplossing |
|---|---|---|
| **WinRM Authorization Error na Active Directory promotie** | Nadat server1 domeincontroller wordt, weigert WinRM standaard NTLM/Negotiate authenticatie via de doorgestuurde Vagrant-poort. | In de `Vagrantfile` is het WinRM-transport geforceerd ingesteld op `:plaintext` met `basic_auth_only = true`, gecombineerd met verhoogde `retry_limit` en `retry_delay`. |
| **`Install-ADDSForest` stelde functional level in op 2016** | De parameter `-ForestMode` / `-DomainMode` gebruikte aanvankelijk `WinThreshold` (Windows Server 2016). | De parameters zijn expliciet aangepast naar `"Win2025"` om het Windows Server 2025 functional level af te dwingen. |
| **HTTP 403.4 fout bij Web Enrollment `/CertSrv`** | IIS Web Enrollment vereist standaard een veilige HTTPS-verbinding en weigert rechtstreekse HTTP-aanvragen. | Een aparte IIS-redirectsite aangemaakt op poort 80 die HTTP-verkeer via een `302 Found` status direct doorstuurt naar `https://server3.WS26-JD.hogent/certsrv/Default.asp`. |
| **Scheduled Task voor CA AD-publicatie faalde** | Het rechtstreeks uitvoeren van `certutil -dspublish` vanuit een PowerShell Scheduled Task miste de juiste execution context. | De taak hergeschreven zodat `cmd.exe` de `certutil`-opdracht uitvoert met expliciete logging naar `C:\ProgramData\WS2-PublishRootCA.log`. |
| **WinRM poort geblokkeerd na inschakelen Firewall** | De regel voor WinRM bevatte een te strikt `-Service 'WinRM'` filter, waardoor doorgestuurd NAT-verkeer werd afgewezen. | Het service-filter op de beheerregel `WS2-Managed-WinRM-NAT` versoepeld naar `-Service 'Any'`, terwijl de strikte bronadres- (`10.0.2.2`) en poortbeperkingen (`5985`) behouden bleven. |
| **Parameterconflict bij herhaalde Firewall provisioning** | `Set-NetFirewallRule` faalde doordat `DisplayName` en `Group` tegelijk als selectie- en updateparameters werden meegegeven. | Functie `Set-LabAllowRule` aangepast: update-parameters gekloond, `DisplayName` en `Group` verwijderd, en `NewDisplayName` gebruikt voor het hernoemen. |
| **Client ontving de CA Trust GPO niet** | De Windows 11 client was nog geen lid van het Active Directory domein ten tijde van de GPO-toepassing. | Script `join-domain.ps1` toegevoegd aan de client-provisioning vian de `Vagrantfile` *vóór* het uitvoeren van de CA-verificatie. |

---

## 3. Deel 3: Conclusie & Reflectie

### 3.1 Wat heb je geleerd?

* **Afhankelijkheidsbeheer in complexe netwerken:** Het uitrollen van een Windows Server-bedrijfsomgeving vereist een zeer strakke volgorde: netwerk-IP's $\rightarrow$ Active Directory $\rightarrow$ DNS $\rightarrow$ Domain Join van secundaire servers $\rightarrow$ Certificate Authority $\rightarrow$ GPO uitrol $\rightarrow$ Client Join.
* **Idempotentie in PowerShell:** Scripts moeten zó geschreven worden dat ze meerdere keren achter elkaar uitgevoerd kunnen worden zonder foutmeldingen te genereren of dubbele objecten aan te maken.
* **WinRM & Firewall Interoperabiliteit:** Diepgaand inzicht verkregen in hoe Windows Defender Firewall omgaat met RPC dynamic ports, WinRM listeners, NAT-gateways en service-specific filters op Server Core-edities.
* **PKI & Certificaatketens:** Praktische ervaring opgedaan met het opzetten van een Enterprise Root CA, het publiceren van certificaten in Active Directory LDAP-stores, en het distribueren van vertrouwen via Group Policies.

---

### 3.2 Wat zou je in de toekomst anders doen?

* **Onafhankelijke Verificatie-provisioners:** Vanaf dag één de configuratiescripts en de acceptatietesten (verificatiescripts) strikt gescheiden houden. Dit maakte het opsporen en isoleren van bugs in een later stadium veel eenvoudiger.
* **Modulaire Firewall-opbouw:** In plaats van één groot firewallscript, het instellen van specifieke firewallregels direct meenemen in de betreffende rol-scripts (bv. DNS-regels direct in de DNS-scripts, IIS-regels in het IIS-script).

---

### 3.3 Aan welke zaken is veel tijd verloren gegaan?

1. **WinRM-instabiliteit na DC-promotie:** Het uitzoeken waarom Vagrant de verbinding met server1 verloor na de promotie tot domeincontroller heeft veel tijd gekost (opgelost door `:plaintext` basic auth instellingen).
2. **IIS HTTPS Binding & Redirect logica op server3:** Het combineren van een geldige certificaataanvraag via een Scheduled Task onder domein-credentials, IIS SSL-flags en een anonieme HTTP-toegankelijke 302-redirect vereiste veel trial-and-error.
3. **Firewall-debugging op Server Core:** Omdat de servers geen GUI hebben, moest elk firewallprobleem opgelost worden via PowerShell, SSH en `netsh advfirewall`, wat meer precisie vereiste bij het uitlezen van event logs en actieve netwerkverbindingen.
