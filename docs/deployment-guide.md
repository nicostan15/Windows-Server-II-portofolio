# Deployment Guide (draft)

> Dit bestand is een werkdocument. Bij indienen zet je de finale, verzorgde versie om naar `readme.pdf`
> (max 8 bladzijden), met naam en klasgroep erop.

## 1. Vereisten

- VirtualBox 7.2.x
- Vagrant (`winget install Hashicorp.Vagrant` of via vagrantup.com)
- Minstens 16 GB RAM (24-32 GB aangeraden)

## 2. Stappen om de omgeving uit te rollen

1. Clone deze repository.
2. Ga naar de map met de `Vagrantfile`.
3. Voer uit: `vagrant up` (of per VM: `vagrant up server1`, `vagrant up server2`, ...).
4. Bij het uitrollen van **server1** gebeurt automatisch het volgende (geen manuele actie nodig):
   - `scripts/configure-network.ps1` stelt het statische IP in op de Host-Only interface (192.168.26.10/24).
   - `scripts/server1/promote-dc.ps1` installeert de AD-Domain-Services rol en promoveert server1 tot
     domeincontroller van een nieuw forest `WS26-JD.hogent`, met forest- en domain functional level
     Windows Server 2025 (DNS-rol wordt automatisch mee geïnstalleerd).
   - Vagrant herstart de VM zelf na deze promotie (`reboot: true` in de Vagrantfile) en wacht tot de
     VM terug bereikbaar is via WinRM.
5. Bij het uitrollen van **server2** en **server3** wordt enkel het statische Host-Only IP ingesteld
   (192.168.26.20 en 192.168.26.30) via hetzelfde `configure-network.ps1`-script.
6. Verifieer na het uitrollen van server1:
   ```powershell
   vagrant ssh server1
   powershell
   Get-ADDomain | Select-Object Name, DomainMode
   Get-ADForest | Select-Object Name, ForestMode
   Get-NetIPConfiguration -InterfaceAlias "Ethernet 2"
   ```
   Verwacht resultaat: `DomainMode: Windows2025Domain`, `ForestMode: Windows2025Forest`,
   IP-adres `192.168.26.10`.
7. ... (vul aan naarmate je scripts voor DNS, DHCP, CA, IIS en firewall klaar zijn)

## 3. Gebruikers en wachtwoorden

| Gebruikersnaam | Rol | Wachtwoord |
|---|---|---|
| vagrant | Domain Admin (automatisch lid gemaakt na promotie, zie sectie 4) | standaard vagrant-wachtwoord |
| Administrator | Domain Admin (standaard account van het forest) | zelfde als lokaal Administrator-wachtwoord vóór promotie |
| TODO | Domain User | TODO |
| TODO | Domain User | TODO |

> DSRM (Directory Services Restore Mode) wachtwoord voor server1: zie parameter `-SafeModePassword`
> in `scripts/server1/promote-dc.ps1`. Dit is apart van de bovenstaande domain-accounts.

## 4. Status van het project

**Wat is af:**
- Host-Only IP-configuratie van server1, server2 en server3 (via `configure-network.ps1`), idempotent
  en volledig geautomatiseerd via Vagrant provisioning.
- VirtualBox interne DHCP-server gecontroleerd en bevestigd uitgeschakeld op het Host-Only netwerk
  (stond al uit dankzij `auto_config: false` in de Vagrantfile).
- server1 gepromoveerd tot domeincontroller van forest `WS26-JD.hogent`, met forest- en domain
  functional level Windows Server 2025, volledig geautomatiseerd via `vagrant up server1`
  (script `scripts/server1/promote-dc.ps1`).

**Wat is nog niet af:**
- OU-structuur (minstens 3 OU's) en gebruikers (minstens 2 Domain Admin, 2 Domain User) scripten.
- DNS (forward/reverse zone, A/PTR-records, secundaire DNS op server2, zone transfers).
- DHCP-rol en scope op server3.
- Certification Authority op server3 + GPO voor automatisch vertrouwen.
- IIS-installatie op server1 met "Hello World"-pagina.
- RSAT-tools op de Windows 11 client.
- Firewallregels per server (enkel noodzakelijk inkomend verkeer).

**Problemen en oplossingen:**

| Probleem | Oorzaak | Oplossing |
|---|---|---|
| `Get-NetAdapter` niet herkend | Per ongeluk in cmd.exe i.p.v. PowerShell gewerkt | Typ `powershell` om over te schakelen |
| Ping tussen servers faalde (TimedOut) | Windows Defender Firewall blokkeert ICMP standaard op alle profielen | Tijdelijk uitgeschakeld ter test; structurele oplossing (gerichte regels) gepland bij de firewall-taak |
| `Install-ADDSForest` zette functional level op Windows Server 2016 i.p.v. 2025 | Parameterwaarde `WinThreshold` komt overeen met Server 2016, niet 2025 (verouderde online voorbeelden gebruiken deze waarde) | Correcte waarde `Win2025` gebruikt in `-ForestMode`/`-DomainMode` |
| `Set-ADForestMode`/`Set-ADDomainMode` gaf "Insufficient access rights" | Het `vagrant`-account krijgt bij domain-promotie geen automatisch lidmaatschap van Enterprise Admins/Domain Admins, ondanks lokale Administrator-rechten vooraf | Account expliciet toegevoegd via `Add-ADGroupMember`, gevolgd door een volledige VM-herstart (`vagrant reload`) zodat de nieuwe groepslidmaatschap in het token werd opgenomen |
| `vagrant up` crashte met `WinRM::WinRMAuthorizationError` net na een succesvolle AD-promotie | De standaard WinRM negotiate/NTLM-authenticatie van Vagrant stopt met werken zodra de server domeincontroller wordt, waardoor Vagrant de shell niet meer netjes kan afsluiten (bekend/gedocumenteerd Vagrant-probleem) | WinRM-transport in de Vagrantfile globaal omgezet naar `plaintext` met `basic_auth_only = true`, en de retry-limiet/-delay verhoogd zodat Vagrant voldoende tijd krijgt om de server na de reboot terug te vinden |
| Na een gecrashte `vagrant up` kon een nieuwe `server1` niet aangemaakt worden (`VERR_ALREADY_EXISTS`) | Verweesde VirtualBox-bestandsmap van de gecrashte poging bleef op schijf staan | VM unregistered en verweesde map handmatig verwijderd (`VBoxManage unregistervm --delete` + controle met `Test-Path`) vóór een nieuwe `vagrant up` |

## 5. Conclusie

- Wat heb je geleerd?
- Wat zou je anders doen?
- Waaraan verloor je (te) veel tijd?