# Deployment Guide — Windows Server II Portofolio

> Dit bestand is een werkdocument. Bij indienen zet je de finale, verzorgde versie om naar `readme.pdf`  
> (max 8 bladzijden), met naam en klasgroep erop.

## 1. Vereisten

- VirtualBox 7.2.x
- Vagrant (`winget install Hashicorp.Vagrant` of via vagrantup.com)
- Minstens 16 GB RAM (24–32 GB aanbevolen)
- Windows-host met PowerShell
- Voldoende vrije schijfruimte voor drie Windows Server-VM’s en één Windows 11-client

## 2. Stappen om de omgeving uit te rollen

1. Clone deze repository.
2. Ga naar de map met de `Vagrantfile`.
3. Voer uit:

```powershell
vagrant up
```

Of per VM:

```powershell
vagrant up server1
vagrant up server2
vagrant up server3
vagrant up client
```

4. Bij het uitrollen van **server1** gebeurt automatisch het volgende, zonder manuele actie:

- `scripts/configure-network.ps1` stelt het statische IP in op de Host-Only interface: `192.168.26.10/24`.
- `scripts/server1/promote-dc.ps1` installeert Active Directory Domain Services en promoveert server1 tot domeincontroller van het nieuwe forest `WS26-JD.hogent`.
- Het forest- en domeinfunctional level wordt ingesteld op Windows Server 2025.
- De DNS-rol wordt automatisch mee geïnstalleerd.
- Vagrant herstart server1 na de promotie en wacht tot de VM opnieuw bereikbaar is via WinRM.
- `scripts/server1/create-ous-users.ps1` maakt de vereiste OU-structuur en gebruikers aan.
- IIS wordt geïnstalleerd en de intranetwebsite wordt geconfigureerd op `intranet.WS26-JD.hogent`.

5. Bij het uitrollen van **server2** en **server3** wordt het statische Host-Only IP ingesteld:

- server2: `192.168.26.20/24`
- server3: `192.168.26.30/24`

6. De DNS-configuratie wordt geautomatiseerd uitgerold:

- server1 bevat de primaire DNS-zones.
- server2 bevat de secundaire DNS-zones.
- Forward- en reverse-lookupzones worden aangemaakt.
- A- en PTR-records worden voor server1, server2 en server3 geconfigureerd.
- Een A-record voor `intranet.WS26-JD.hogent` verwijst naar `192.168.26.10`.
- Zone transfers en de benodigde DNS-firewallregels worden ingesteld.

7. De Enterprise Root CA, Web Enrollment en DHCP op server3 worden geautomatiseerd uitgerold:

- De Active Directory Certificate Services-rol wordt geïnstalleerd.
- De Enterprise Root CA `WS26-JD-Root-CA` wordt geconfigureerd.
- Het publieke rootcertificaat wordt geëxporteerd naar `C:\LabCertificates\WS26-JD-Root-CA.cer`.
- De Web Enrollment-rol wordt geïnstalleerd.
- Een websitecertificaat voor `server3.WS26-JD.hogent` wordt aangevraagd en aan IIS gekoppeld.
- HTTPS wordt geconfigureerd op poort 443.
- De HTTP-ingang wordt omgezet naar een HTTP 302-redirect naar HTTPS.
- Het rootcertificaat wordt automatisch gepubliceerd in Active Directory via `server3-publish-root-ca`.
- De DHCP-serverrol, scope, exclusies en DHCP-opties worden geconfigureerd.

8. Na het opstarten van server3 worden automatisch de CA-afhankelijke stappen op server1 uitgevoerd via een Vagrant-trigger:

- Het webserver-certificaattemplate wordt geconfigureerd.
- De GPO `WS26 - Vertrouw Root CA` wordt aangemaakt en aan het domein gekoppeld.
- Web Enrollment wordt automatisch gecontroleerd vanaf server1.
- De Root-CA-trust op server1 wordt gecontroleerd.

9. Bij het uitrollen van de **client** gebeurt automatisch het volgende:

- De Host-Only-interface verkrijgt een IP-adres via DHCP.
- RSAT-tools worden geïnstalleerd.
- De firewall wordt ingeschakeld met een minimale configuratie.
- De client wordt toegevoegd aan het domein `WS26-JD.hogent` en herstart.
- Na de herstart wordt Group Policy vernieuwd.
- De Root-CA-trust en de bereikbaarheid van het intranet worden automatisch gecontroleerd.

10. Verifieer na het uitrollen van server1:

```powershell
vagrant ssh server1
powershell

Get-ADDomain | Select-Object Name, DomainMode
Get-ADForest | Select-Object Name, ForestMode
Get-NetIPConfiguration -InterfaceAlias "Ethernet 2"
Get-ADOrganizationalUnit -Filter *
Get-ADUser -Filter *
```

Verwacht resultaat:

- `DomainMode: Windows2025Domain`
- `ForestMode: Windows2025Forest`
- IP-adres: `192.168.26.10`
- OU’s: `Beheer`, `Medewerkers`, `Servers`, `Clients`
- Gebruikers: `j.doe.adm`, `a.smit.adm`, `p.jansen`, `m.peeters`

11. Verifieer de DNS-replicatie vanaf server2:

```powershell
vagrant ssh server2
powershell

Get-DnsServerZone |
    Where-Object ZoneType -eq "Secondary" |
    Select-Object ZoneName, ZoneType, MasterServers
```

Verwacht resultaat: de forward-, reverse- en `_msdcs`-zones zijn aanwezig als Secondary zones.

12. Verifieer de CA-publicatie:

```powershell
vagrant provision server3 --provision-with server3-publish-root-ca
```

Verwacht resultaat:

```text
Certificate already in DS store.
CertUtil: -dsPublish command completed successfully.
Root-CA-certificaat is gepubliceerd in Active Directory.
```

13. Verifieer de CA en Web Enrollment vanaf server1:

```powershell
vagrant provision server1 --provision-with server1-verify-web-enrollment
```

Verwacht resultaat:

```text
server1: Controle Web Enrollment vanaf server1...
server1: HTTP-ingang: http://server3.WS26-JD.hogent/CertSrv/
server1: HTTP-redirect: 302 naar [https://server3.WS26-JD.hogent/certsrv/Default.asp](https://server3.WS26-JD.hogent/certsrv/Default.asp)
server1: HTTPS-pagina: HTTP 200
server1: Paginatitel: Microsoft Active Directory Certificate Services
server1: Web Enrollment is correct bereikbaar via http://server3.WS26-JD.hogent/CertSrv/.
```

14. Verifieer het intranet:

```powershell
vagrant ssh server1
powershell

Resolve-DnsName intranet.WS26-JD.hogent
Invoke-WebRequest -Uri "http://intranet.WS26-JD.hogent" -UseBasicParsing |
    Select-Object StatusCode, StatusDescription
```

Verwacht resultaat:

```text
IPAddress : 192.168.26.10
StatusCode: 200
```

15. Verifieer de client:

```powershell
vagrant provision client --provision-with client-verify-ca
```

Verwacht resultaat:

```text
client: Root-CA aanwezig:
client: Intranet is bereikbaar: HTTP 200.
```

16. Verifieer SSH-toegang met actieve firewall:

```powershell
vagrant ssh server1
vagrant ssh server2
vagrant ssh server3
vagrant ssh client
```

Verwacht resultaat: elke opdracht opent een shell op de betreffende VM zonder dat de firewall uitgeschakeld moet worden.

## 3. Gebruikers en wachtwoorden

| Gebruikersnaam | Rol | Wachtwoord |
|---|---|---|
| `vagrant` | Domain Admin, automatisch lid gemaakt na AD-promotie | standaard Vagrant-wachtwoord |
| `Administrator` | Domain Admin, standaardaccount van het forest | zelfde wachtwoord als het lokale Administrator-account vóór promotie |
| `j.doe.adm` | Domain Admin | zie `scripts/server1/create-ous-users.ps1` |
| `a.smit.adm` | Domain Admin | zie `scripts/server1/create-ous-users.ps1` |
| `p.jansen` | Domain User | zie `scripts/server1/create-ous-users.ps1` |
| `m.peeters` | Domain User | zie `scripts/server1/create-ous-users.ps1` |

> Het DSRM-wachtwoord voor server1 staat in de parameter `-SafeModePassword` van `scripts/server1/promote-dc.ps1`. Dit is een apart wachtwoord van de domeinaccounts.

> Het Administrator-wachtwoord dat door de Web Enrollment-verificatie wordt gebruikt, staat in de Vagrantfile als waarde van `WS26_ADMIN_PASSWORD`. Het verificatiescript zelf bevat het wachtwoord niet.

## 4. Netwerkoverzicht

| Machine | Host-Only IP | Functie |
|---|---|---|
| server1 | `192.168.26.10` | Domeincontroller, primaire DNS, IIS/intranet |
| server2 | `192.168.26.20` | Secundaire DNS |
| server3 | `192.168.26.30` | Enterprise Root CA, Web Enrollment, DHCP |
| client | DHCP | Windows 11-domeinlid met RSAT |

## 5. Status van het project

### Wat is af

- Host-Only IP-configuratie van server1, server2 en server3 via `scripts/configure-network.ps1`.
- VirtualBox-interne DHCP-server gecontroleerd en bevestigd uitgeschakeld op het Host-Only netwerk.
- server1 gepromoveerd tot domeincontroller van forest `WS26-JD.hogent`.
- Forest- en domeinfunctional level ingesteld op Windows Server 2025.
- DNS-rol geïnstalleerd tijdens de domeincontrollerpromotie.
- OU-structuur aangemaakt: `Beheer`, `Medewerkers`, `Servers` en `Clients`.
- Vier domeingebruikers aangemaakt: twee Domain Admins en twee Domain Users.
- DNS-primaire zones, reverse zones, A-records, PTR-records en `_msdcs`-zone geconfigureerd op server1.
- A-record voor `intranet.WS26-JD.hogent` toegevoegd en getest.
- DNS secundaire zones, zone transfers en DNS-firewallregels geconfigureerd op server2.
- Enterprise Root CA `WS26-JD-Root-CA` geïnstalleerd en geconfigureerd op server3.
- Publiek CA-rootcertificaat geëxporteerd naar `C:\LabCertificates\WS26-JD-Root-CA.cer`.
- CA Web Enrollment-rol geïnstalleerd en de `/CertSrv`-applicatie geconfigureerd.
- Websitecertificaat voor `server3.WS26-JD.hogent` aangevraagd en aan IIS gekoppeld.
- HTTPS-binding op poort 443 geconfigureerd.
- HTTP-ingang naar Web Enrollment geconfigureerd als HTTP 302-redirect naar HTTPS.
- Root-CA-certificaat automatisch gepubliceerd in Active Directory.
- GPO `WS26 - Vertrouw Root CA` aangemaakt en gekoppeld aan het domein.
- Automatische CA-trust gecontroleerd op server1 en de Windows 11-client.
- DHCP-serverrol, scope `192.168.26.100–192.168.26.200`, exclusies en DHCP-opties geconfigureerd.
- IIS geïnstalleerd op server1 met een bereikbare intranetpagina via `http://intranet.WS26-JD.hogent`.
- RSAT-tools automatisch geïnstalleerd op de Windows 11-client.
- Windows 11-client automatisch toegevoegd aan het domein `WS26-JD.hogent`.
- Firewall ingeschakeld op alle VM’s met `Block` voor inkomend en `Allow` voor uitgaand verkeer.
- Minimale firewallregels geconfigureerd voor DNS, HTTP, HTTPS, WinRM, Core Networking en SSH.
- `vagrant ssh` getest op alle vier VM’s met actieve firewall.
- Volledige provisioning-automatisering toegevoegd zodat `vagrant up` de omgeving opbouwt zonder handmatige provision-stappen.

### Wat is nog niet af

- Een volledige end-to-end herbouw met `vagrant destroy -f` gevolgd door `vagrant up` moet nog één keer definitief worden gevalideerd.

### Problemen en oplossingen

| Probleem | Oorzaak | Oplossing |
|---|---|---|
| `Get-NetAdapter` niet herkend | Per ongeluk in `cmd.exe` gewerkt in plaats van PowerShell | Overgeschakeld naar PowerShell met `powershell` |
| Ping tussen servers faalde met `TimedOut` | Windows Defender Firewall blokkeert ICMP standaard | Tijdelijk uitgeschakeld voor testen; structurele oplossing met gerichte firewallregels uitgewerkt tijdens de DNS-taak |
| `Install-ADDSForest` gebruikte Windows Server 2016 als functional level | Parameterwaarde `WinThreshold` komt overeen met Windows Server 2016 | Correcte waarde `Win2025` gebruikt voor `-ForestMode` en `-DomainMode` |
| `Set-ADForestMode` / `Set-ADDomainMode` gaf “Insufficient access rights” | Het `vagrant`-account was na de promotie geen lid van de vereiste beheergroepen | Account expliciet toegevoegd aan `Domain Admins` / `Enterprise Admins`, gevolgd door een volledige herstart |
| `vagrant up` crashte met `WinRM::WinRMAuthorizationError` na AD-promotie | Standaard WinRM negotiate/NTLM-authenticatie werkt niet meer nadat de server domeincontroller wordt | WinRM-transport omgezet naar `plaintext` met `basic_auth_only = true`; retry-limiet en delay verhoogd |
| Na een gecrashte `vagrant up` kon server1 niet opnieuw worden aangemaakt (`VERR_ALREADY_EXISTS`) | Verweesde VirtualBox-map bleef achter | VM uitgeschreven met `VBoxManage unregistervm --delete` en de achtergebleven map verwijderd |
| DNS-firewallblok gaf een parameterconflict | `DisplayName` werd tegelijk gebruikt als selectie- en wijzigingsparameter | Selectie via `Name` en hernoeming via `NewDisplayName` |
| Directe HTTPS-aanvraag naar `/CertSrv` werkte, maar HTTP gaf `403.4` | De Certificate Services-pagina vereist HTTPS | Aparte HTTP-redirectsite toegevoegd die HTTP 302 stuurt naar de HTTPS-startpagina |
| PowerShell-authenticatie na een automatische HTTP-naar-HTTPS-redirect gaf problemen | Credentials worden niet betrouwbaar meegestuurd over de redirect | Redirect expliciet gecontroleerd zonder credentials; daarna pas de HTTPS-bestemming opgevraagd met credentials |
| `server3-publish-root-ca` faalde omdat het publicatielog ontbrak | De samengestelde `powershell.exe -Command`-argumenten startten `certutil` niet betrouwbaar in de Scheduled Task | Script aangepast zodat `cmd.exe` de `certutil`-opdracht uitvoert met een eenvoudige `>`- en `2>&1`-omleiding naar het logbestand |
| Client ontving de CA-trust-GPO niet | De client was nog geen lid van het domein | Client automatisch toegevoegd aan `WS26-JD.hogent`; daarna werd de GPO toegepast en verscheen het Root-CA-certificaat in de Trusted Root-store |
| `WinRM::WinRMAuthorizationError` tijdens de client-domeinjoin | `Add-Computer -Restart` herstartte de client terwijl Vagrant nog verbonden was | Verwacht gedrag; na de herstart werd de verbinding hersteld en slaagde de verdere provisioning |
| `vagrant ssh` leek mogelijk geblokkeerd door de firewall | Inkomend verkeer wordt standaard geblokkeerd | De bestaande regel `OpenSSH-Server-In-TCP` bleef ingeschakeld; SSH werd getest op alle vier VM’s met actieve firewall |

## 6. Conclusie

- Het uitrollen van een Windows Server-labomgeving is volledig herhaalbaar gemaakt met Vagrant en idempotente PowerShell-scripts.
- De omgeving omvat nu Active Directory, DNS, DHCP, Certification Authority, Web Enrollment, IIS, RSAT, client-domeinjoin, firewallbeleid en automatische verificatie.
- De belangrijkste leerervaring was dat Active Directory, DNS, certificaten, IIS en firewallregels sterk van elkaar afhankelijk zijn: een CA heeft correcte DNS nodig, Web Enrollment heeft een correct certificaat nodig, en verificatie vanaf een andere server controleert de volledige keten.
- Idempotentie is essentieel gebleken: scripts moeten veilig opnieuw kunnen draaien zonder dubbele objecten of onnodige wijzigingen aan te maken.
- De Vagrantfile is zo opgebouwd dat de volgorde van afhankelijkheden automatisch wordt gerespecteerd: eerst de domeincontroller, daarna DNS en CA, vervolgens de CA-afhankelijke server1-configuratie en ten slotte de client.
- Bij een volgend project zou ik vanaf het begin een aparte verificatieprovisioner per dienst toevoegen, zodat configuratie en acceptatietest gescheiden blijven.
- De meeste tijd ging verloren aan Windows-specifieke gedragingen: firewallregels, WinRM na domeinpromotie, certificaatbindingen in IIS, authenticatiegedrag bij redirects en Scheduled Task-quoting in PowerShell.