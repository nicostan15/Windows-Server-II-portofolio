# Status log

Bijgehouden tijdens het project: datum, uitgevoerde werkzaamheden, problemen, oplossingen en testresultaten.

## 2026-09-23 — Repository en projectstructuur

- Repository en mapstructuur opgezet.
- Opvolgpunt genoteerd: Vagrantfile van Orion toevoegen.

***

## 2026-09-30 — Host-Only-netwerkconfiguratie

- Host-Only IP-configuratie ingesteld via PowerShell:
  - server1: `192.168.26.10/24`
  - server2: `192.168.26.20/24`
  - server3: `192.168.26.30/24`
- Interfaces geïdentificeerd met `Get-NetAdapter` en `Get-NetIPConfiguration`.
- Connectiviteit getest met `Test-NetConnection`.
- Vastgesteld dat Windows Defender Firewall ICMP-verkeer blokkeerde.
- Firewall tijdelijk uitgeschakeld voor netwerkdiagnostiek; gerichte firewallregels als structurele oplossing voorzien.
- Herbruikbaar script gemaakt: `scripts/configure-network.ps1`.
- VirtualBox-interne DHCP-server gecontroleerd en bevestigd uitgeschakeld op het gebruikte Host-Only-netwerk.
- Netwerkconfiguratie geautomatiseerd via Vagrant provisioning.
- Status Week 2, deel 1/2: Host-Only IP-configuratie en DHCP-check afgerond.

***

## 2026-10-14 — Active Directory, OU’s en gebruikers

- `vagrant up server1` succesvol doorlopen, inclusief AD-promotie en herstart.
- WinRM-workaround bevestigd:
  - Transport: `plaintext`
  - `basic_auth_only = true`
  - Verhoogde retry-instellingen
- Functional levels geverifieerd:
  - `Windows2025Domain`
  - `Windows2025Forest`
- Netwerkconfiguratie na promotie gecontroleerd.
- Definitieve opdrachtversie gecontroleerd tegen de draft.
- Script gemaakt: `scripts/server1/create-ous-users.ps1`.
- Vier OU’s geautomatiseerd aangemaakt:
  - `Beheer`
  - `Medewerkers`
  - `Servers`
  - `Clients`
- Vier gebruikers geautomatiseerd aangemaakt:
  - `j.doe.adm`
  - `a.smit.adm`
  - `p.jansen`
  - `m.peeters`
- Groepslidmaatschappen gecontroleerd:
  - `j.doe.adm` en `a.smit.adm`: Domain Admins
  - `p.jansen` en `m.peeters`: Domain Users, geen Domain Admins
- Status Week 2, deel 2/2: DC-promotie, functional levels, OU-structuur en gebruikers afgerond.

***

## 2026-10-20 — DNS-automatisatie en herhaalbaarheid

- Primaire DNS-script uitgebreid met DNS-firewallregels en NS-/transferinstellingen.
- Parameterconflict in het firewallblok opgelost.
- `dns-primary` en `dns-secondary` elk tweemaal succesvol uitgevoerd.
- Na herprovisioning op server2 bevestigd dat alle drie labzones Secondary zijn:
  - `WS26-JD.hogent`
  - `_msdcs.WS26-JD.hogent`
  - `26.168.192.in-addr.arpa`
- A- en PTR-records van server1, server2 en server3 gecontroleerd.
- Geen NAT-IP-adressen aanwezig in de gecontroleerde A-records.
- DNS-configuratie en herhaalde provisioning geverifieerd.

***

## 2026-10-21 — Enterprise Root CA, Web Enrollment en automatische verificatie

- `scripts/server3/03-ca.ps1` uitgebreid en uitgevoerd voor de installatie en configuratie van Active Directory Certificate Services op server3.
- Enterprise Root CA `WS26-JD-Root-CA` geïnstalleerd en geconfigureerd.
- CA-service `CertSvc` gecontroleerd en actief bevonden.
- Publiek CA-rootcertificaat geëxporteerd naar:

```text
C:\LabCertificates\WS26-JD-Root-CA.cer
```

- Certificaatdetails gecontroleerd: subject, issuer, thumbprint en geldigheidsperiode.
- CA Web Enrollment-rol geïnstalleerd.
- `/CertSrv`-webapplicatie gecontroleerd in IIS.
- Websitecertificaat voor `server3.WS26-JD.hogent` aangevraagd bij de eigen Enterprise Root CA.
- Websitecertificaat gecontroleerd op subject, issuer, private key en geldigheid.
- HTTPS-binding op poort 443 geconfigureerd in IIS.
- HTTPS-toegang tot `/CertSrv` getest met domeincredentials; resultaat was HTTP `200`.
- Directe HTTP-toegang tot `/CertSrv` gaf aanvankelijk HTTP `403.4`, omdat de Certificate Services-pagina HTTPS vereist.
- Aparte IIS-redirectsite toegevoegd voor de HTTP-ingang.
- HTTP-redirect geconfigureerd met status `302 Found` naar:

```text
[https://server3.WS26-JD.hogent/certsrv/Default.asp](https://server3.WS26-JD.hogent/certsrv/Default.asp)
```

- Redirectsite expliciet ingesteld op anonieme toegang, zonder Windows-authenticatie en zonder SSL-vereiste.
- Bestaande HTTPS-site en HTTPS-certificaatbinding behouden.
- Interne HTTP-firewallregel bevestigd voor toegang tot server3 op poort 80.
- Nieuw verificatiescript gemaakt: `scripts/server1/04-verify-web-enrollment.ps1`.
- Verificatiescript toegevoegd aan de Vagrantfile als provisioner `server1-verify-web-enrollment`.
- Administrator-wachtwoord via de Vagrantfile doorgegeven als omgevingsvariabele `WS26_ADMIN_PASSWORD`.
- Verificatiescript getest met:

```powershell
vagrant provision server1 --provision-with server1-verify-web-enrollment
```

- Geslaagde automatische controle bevestigd:

```text
HTTP-ingang: http://server3.WS26-JD.hogent/CertSrv/
HTTP-redirect: 302 naar [https://server3.WS26-JD.hogent/certsrv/Default.asp](https://server3.WS26-JD.hogent/certsrv/Default.asp)
HTTPS-pagina: HTTP 200
Paginatitel: Microsoft Active Directory Certificate Services
```

- Checklistpunt afgerond:

```markdown
- [x] Web Enrollment Role Service testen via http://FQDN/CertSrv
```

- Opvolgpunt genoteerd: certificaathergebruik controleren en verbeteren, zodat herhaalde provisioning niet onnodig nieuwe websitecertificaten aanvraagt.
- Dit opvolgpunt werd verder onderzocht en functioneel getest op 27 oktober.

***

## 2026-10-22 — Automatische CA-trust via Active Directory en GPO

- Nieuw script gemaakt: `scripts/server3/06-publish-root-ca.ps1`.
- Het script publiceert het publieke rootcertificaat van `WS26-JD-Root-CA` in Active Directory.
- Publicatie uitgevoerd met een tijdelijke Scheduled Task onder het domein-Administratoraccount.
- Publicatie gecontroleerd met:

```powershell
vagrant provision server3 --provision-with server3-publish-root-ca
```

- Resultaat bevestigd:

```text
Certificate already in DS store.
CertUtil: -dsPublish command completed successfully.
Root-CA-certificaat is gepubliceerd in Active Directory.
```

- Nieuw verificatiescript gemaakt: `scripts/server1/05-trust-root-ca.ps1`.
- Het script controleert herhaaldelijk of server1 het rootcertificaat in de Trusted Root-store heeft ontvangen.
- Verificatie uitgevoerd met:

```powershell
vagrant provision server1 --provision-with server1-trust-root-ca
```

- Rootcertificaat bevestigd op server1 in de toenmalige omgeving:

```text
Subject: CN=WS26-JD-Root-CA, DC=WS26-JD, DC=hogent
Thumbprint: 9BAC7EC5CC2A09C9CC23A8494366AF26248C288B
NotAfter: 10/21/2031 6:44:30 PM
```

- Bestaand script `scripts/server1/configure-ca-trust-gpo.ps1` uitgevoerd.
- GPO `WS26 - Vertrouw Root CA` aangemaakt en gekoppeld aan:

```text
DC=WS26-JD,DC=hogent
```

- GPO ingesteld om het rootcertificaat naar domeinleden te distribueren.
- GPO-toepassing op server1 geforceerd met `gpupdate /force`.
- Toepassing bevestigd met `gpresult /scope computer /r`:

```text
Applied Group Policy Objects
    Default Domain Controllers Policy
    Default Domain Policy
    WS26 - Vertrouw Root CA
```

- Certificaat in de GPO-policy store gecontroleerd:

```text
HKLM:\Software\Policies\Microsoft\SystemCertificates\Root\Certificates\9BAC7EC5CC2A09C9CC23A8494366AF26248C288B
```

- Rootcertificaat aanwezig in `Cert:\LocalMachine\Root` op server1.
- Web Enrollment opnieuw gecontroleerd nadat de GPO was toegepast:
  - HTTP-ingang: `302`-redirect naar HTTPS
  - HTTPS-pagina: HTTP `200`
  - Paginatitel: `Microsoft Active Directory Certificate Services`
- CA-publicatie, GPO-configuratie en verificatie van Web Enrollment afzonderlijk succesvol uitgevoerd.
- Checklistpunt afgerond:

```markdown
- [x] GPO maken zodat CA automatisch vertrouwd wordt door alle domeinleden
```

- Status Week 4 volgens de projectregistratie: DHCP, Certification Authority, CA-trust via GPO en Web Enrollment afgerond.
- Clienttoepassing en volledige herbouw bleven afzonderlijke validatiepunten.

***

## 2026-10-26 t/m 2026-10-27 — IIS, client-domeinjoin, CA-trust en firewall

### Root-CA-publicatie en templatepermissies

- Root-CA-publicatie opnieuw uitgevoerd na correctie van `scripts/server3/06-publish-root-ca.ps1`.
- Probleem vastgesteld: het verwachte publicatielog werd niet aangemaakt.
- Aanroep van de tijdelijke Scheduled Task aangepast:
  - `certutil -dspublish` uitvoeren via `cmd.exe`.
  - Uitvoer en foutuitvoer omleiden naar een logbestand.
  - Taakstatus en laatste taakresultaat tonen.
- Succesvolle uitvoering bevestigd:

```text
Taakstatus: Ready
Laatste taakresultaat: 0
Certificate already in DS store.
CertUtil: -dsPublish command completed successfully.
Root-CA-certificaat is gepubliceerd in Active Directory.
```

- Webserver-certificaattemplate geconfigureerd via `webserver-template`.
- Template-DACL opgeslagen onder het domein-Administratoraccount.
- Expliciete Enroll-Allow-regels gecontroleerd in de uitvoer.

### CA-trust en Web Enrollment

- GPO `WS26 - Vertrouw Root CA` opnieuw aangemaakt/geconfigureerd en aan het domein gekoppeld.
- Root-CA-certificaat bevestigd in `Cert:\LocalMachine\Root` op server1.
- Certificaatgegevens van deze omgeving vastgelegd:

```text
Subject: CN=WS26-JD-Root-CA, DC=WS26-JD, DC=hogent
Thumbprint: 226C58F452BB9970BD08435929CCEF1DE44670F7
NotAfter: 10/26/2031
```

- Deze thumbprint hoort bij deze specifieke CA-installatie en vervangt niet de historische certificaatgegevens van 22 oktober.
- Web Enrollment opnieuw gecontroleerd vanaf server1:

```text
HTTP-ingang: http://server3.WS26-JD.hogent/CertSrv/
HTTP-redirect: 302 naar [https://server3.WS26-JD.hogent/certsrv/Default.asp](https://server3.WS26-JD.hogent/certsrv/Default.asp)
HTTPS-pagina: HTTP 200
Paginatitel: Microsoft Active Directory Certificate Services
```

- CA-bereikbaarheid getest vanaf server1 onder het domein-Administratoraccount:

```powershell
certutil -ping -config "server3.WS26-JD.hogent\WS26-JD-Root-CA"
```

- Resultaat bevestigd:

```text
Server "WS26-JD-Root-CA" ICertRequest2 interface is alive.
CertUtil: -ping command completed successfully.
```

- SSH naar `127.0.0.1:2222` aanvankelijk vanuit server1 uitgevoerd; dit gaf `Connection refused`.
- Daarna dezelfde verbinding vanaf de Windows-host uitgevoerd; aanmelden op server1 lukte.

### IIS en intranet

- IIS op server1 geconfigureerd via `scripts/server1/06-iis.ps1`.
- Statische intranetpagina op poort 80 voorzien.
- DNS-record gecontroleerd:

```text
intranet.WS26-JD.hogent -> 192.168.26.10
```

- HTTP-test uitgevoerd vanaf server1 en de Windows 11-client:

```powershell
Invoke-WebRequest `
    -Uri "http://intranet.WS26-JD.hogent" `
    -UseBasicParsing |
    Select-Object StatusCode, StatusDescription
```

- Beide tests gaven:

```text
StatusCode StatusDescription
---------- -----------------
       200 OK
```

### Windows 11-client en RSAT

- RSAT-installatie opgenomen in de provisioning via:

```text
scripts/client/02-install-rsat.ps1
```

- Provisioner `client-rsat` toegevoegd aan de Vagrantfile.
- Client ontving aanvankelijk het Root-CA-certificaat niet:
  - Geen overeenkomstig certificaat in `Cert:\LocalMachine\Root`.
  - Verwachte policy-registersleutel gaf `False`.
- Domeinjoin toegevoegd via:

```text
scripts/client/04-join-domain.ps1
```

- Provisioner `client-domain` toegevoegd vóór de CA-verificatie.
- Tijdens de domeinjoin/herstart trad een `WinRM::WinRMAuthorizationError` op.
- Na de herstart was provisioning opnieuw mogelijk.
- Group Policy vernieuwd en Root-CA-trust op de client succesvol gecontroleerd.
- Nieuw verificatiescript gemaakt:

```text
scripts/client/03-verify-ca.ps1
```

- Toegevoegd als provisioner `client-verify-ca` met `run: "always"`.
- Resultaat bevestigd:

```text
Computer Policy update has completed successfully.
User Policy update has completed successfully.
Root-CA aanwezig:
Intranet is bereikbaar: HTTP 200.
```

- Afzonderlijke controle van de exact geïnstalleerde RSAT-capabilities opgenomen in het testdocument.

### Clientfirewall

- Vastgesteld dat het gedeelde serverfirewallscript de client expliciet weigert:

```text
Dit script configureert alleen de drie servers.
```

- Apart clientscript gemaakt:

```text
scripts/client/configure-client-firewall.ps1
```

- Clientprovisioner aangepast om dit afzonderlijke script te gebruiken.
- Uitvoering succesvol getest.
- Alle drie clientfirewallprofielen gecontroleerd:

```text
Name    Enabled DefaultInboundAction DefaultOutboundAction
----    ------- -------------------- ---------------------
Domain     True                Block                 Allow
Private    True                Block                 Allow
Public     True                Block                 Allow
```

- Clientscript schakelt inkomende Core Networking- en WinRM-regels in.
- Bestaande SSH-toegang behouden.
- Deze profielcontrole bewijst de standaardpolicy; een volledige minimaliteitsaudit van alle uitzonderingen is een afzonderlijke controle.

### SSH met ingeschakelde firewall

- Interactieve SSH-toegang succesvol getest vanaf de host:

```powershell
vagrant ssh server1
vagrant ssh server2
vagrant ssh server3
vagrant ssh client
```

- Elke verbinding afzonderlijk geopend en afgesloten.
- Bestaande OpenSSH-regel op alle vier machines gecontroleerd:

```text
Name                  Enabled Direction Action
----                  ------- --------- ------
OpenSSH-Server-In-TCP    True   Inbound  Allow
```

- Firewall niet volledig uitgeschakeld voor deze SSH-tests.
- Checklistpunt functioneel getest in de toenmalige omgeving:

```markdown
- [x] Testen of vagrant ssh werkt zonder firewall volledig uit te schakelen
```

### Automatisering en documentatie

- Vagrantfile aangepast om handmatige CA-afhankelijke stappen automatisch aan te roepen:
  - `server3-publish-root-ca`: `run: "always"`
  - `webserver-template`: `run: "never"`
  - `ca-trust-gpo`: `run: "never"`
  - `server1-verify-web-enrollment`: `run: "never"`
  - `server1-trust-root-ca`: `run: "never"`
- Server3-trigger toegevoegd om na `:up` de vier CA-afhankelijke server1-provisioners aan te roepen.
- Client-domeinjoin vóór `client-verify-ca` geplaatst.
- Firewallprovisioners opgenomen in de normale opstartflow.
- Testdocument uitgebreid met IIS, intranet, RSAT, domeinjoin, clienttrust, firewall, SSH en volledige herbouw.
- Deployment guide bijgewerkt.
- Automatisering geconfigureerd met als doel uitsluitend `vagrant up` nodig te hebben.
- Succes van een volledige schone herbouw nog niet bevestigd; hiervoor een end-to-end test gepland.

***

## 2026-10-27 — Certificaathergebruik onderzoeken en testen

- `scripts/server3/03-ca.ps1` gecontroleerd op hergebruik van bestaande websitecertificaten.
- Vastgesteld dat het script al een selectieblok voor bestaande certificaten bevatte.
- Aanvankelijk één websitecertificaat aanwezig:

```text
F7F61CFFB575E60B48A77442F82E0D2F9A056D55
```

- CA-provisioner opnieuw uitgevoerd:

```powershell
vagrant provision server3 --provision-with server3-ca
```

- Ondanks het bestaande certificaat werd een tweede certificaat aangevraagd:

```text
4C2E9B11C3AD4134F996A7BB217DA80CA9364F38
```

- Beide certificaten onderzocht:
  - Subject: `CN=server3.WS26-JD.hogent`
  - Private key aanwezig.
  - DNS-naam: `server3.WS26-JD.hogent`
  - Server Authentication-EKU aanwezig.
  - Geldigheid tot oktober 2028.
- De exacte oorzaak waarom het oorspronkelijke selectieblok geen certificaat selecteerde, niet definitief vastgesteld.
- Selectieblok vereenvoudigd naar:
  - Private key aanwezig.
  - Exacte subjectnaam.
  - Meer dan 30 dagen resterende geldigheid.
- CA-provisioner opnieuw uitgevoerd.
- Hergebruik expliciet bevestigd:

```text
Bestaand webservercertificaat wordt hergebruikt.
```

- Gebruikte thumbprint:

```text
4C2E9B11C3AD4134F996A7BB217DA80CA9364F38
```

- HTTPS-binding gecontroleerd en gekoppeld aan dezelfde thumbprint.
- Certificaatlijst na de test bevatte nog steeds twee certificaten; geen derde certificaat aangemaakt.
- Functioneel hergebruik bij herhaalde provisioning daarmee aangetoond.
- Verwijdering van het oudere certificaat niet als uitgevoerd geregistreerd.
- Opvolgpunt: strikte geschiktheidscontrole verbeteren zonder onnodige nieuwe aanvragen, met behoud van controle op geldigheid, DNS-naam, EKU en vertrouwde issuer.
- Deze test bewijst certificaathergebruik in de geteste situatie, niet de volledige idempotentie van alle scripts.

***

## 2026-10-27 — Schone herbouw en WinRM-/firewalldiagnostiek

### Start van de herbouw

- Na het verwijderen van de bestaande omgeving een nieuwe deployment gestart met:

```powershell
vagrant up
```

- server1 opnieuw geïmporteerd vanuit de vastgepinde Windows Server-box.
- Host-Only IP opnieuw ingesteld op `192.168.26.10/24`.
- DNS-registratie op de NAT-interface uitgeschakeld.
- Nieuw forest `WS26-JD.hogent` aangemaakt.
- AD-promotie gaf:

```text
RebootRequired : True
Status         : Success
```

- server1 na promotie opnieuw bereikbaar.
- Domein-Administratorwachtwoord ingesteld.
- Vier OU’s en vier gebruikers opnieuw aangemaakt.
- Primaire DNS-configuratie afgerond:
  - AD-forwardzones beschikbaar.
  - Reverse zone aangemaakt.
  - A- en PTR-records ingesteld.
  - NS-records, zone transfers en notify naar server2 ingesteld.
  - Intranetrecord aangemaakt.
- IIS-installatie en lokale inhoudscontrole succesvol:

```text
Lokale controle: HTTP 200, Hello World gevonden.
```

### Vastlopen tijdens firewallprovisioning

- Firewallscript maakte een back-up en configureerde beheer- en rolregels.
- Daarna bleef Vagrant herhaaldelijk melden:

```text
Attempting graceful shutdown of VM...
```

- Deployment ging niet verder naar server2.
- Tijdens herstel trad een Vagrant-machine-lock op doordat een andere actie nog actief was.
- Vastgelopen acties beëindigd en server1 uiteindelijk via VirtualBox geforceerd uitgeschakeld.
- Latere starts gaven een WinRM-boot-timeout.
- Aanvankelijke vermoedens over een automatische herstart in het firewallscript bleken onjuist:
  - In het gedeelde script stond geen herstartopdracht.
  - VirtualBox-console toonde een normaal opgestarte Windows Server Core-omgeving.
  - SSH naar server1 werkte.
- Windows-herstel of een beschadigde installatie niet aangetoond.
- Diagnose verlegd naar WinRM en firewalltoegang.

### WinRM lokaal controleren

- Op server1 gecontroleerd:

```powershell
Get-Service WinRM | Select-Object Name, Status, StartType
Test-WSMan localhost
winrm enumerate winrm/config/listener
Get-NetTCPConnection -State Listen -LocalPort 5985
```

- Resultaten:
  - WinRM: `Running`
  - Starttype: `Automatic`
  - Lokale WSMan-test geslaagd.
  - HTTP-listener actief op poort `5985`.
  - Listener onder andere beschikbaar op `10.0.2.15` en `192.168.26.10`.
- Authenticatie-instellingen gecontroleerd:
  - `Basic = true`
  - `AllowUnencrypted = true`
- Vanaf de host:
  - TCP-test naar `127.0.0.1:55985` slaagde.
  - `Test-WSMan` naar dezelfde doorgestuurde poort faalde.
- Vastgesteld dat een geslaagde TCP-test alleen onvoldoende bewijs was voor werkende WinRM-communicatie.

### Servicefilter als oorzaak vastgesteld

- Regel `WS2-Managed-WinRM-NAT` gecontroleerd:
  - Enabled: `True`
  - Direction: `Inbound`
  - Action: `Allow`
  - Profile: `Any`
  - Protocol: TCP
  - LocalPort: `5985`
  - RemoteAddress: `10.0.2.2`
  - InterfaceAlias: `Ethernet`
  - Service: `WinRM`
- Alleen het servicefilter gewijzigd:

```powershell
Set-NetFirewallRule `
    -PolicyStore PersistentStore `
    -Name "WS2-Managed-WinRM-NAT" `
    -Service Any
```

- Daarna slaagde de hosttest:

```powershell
Test-WSMan -ComputerName 127.0.0.1 -Port 55985
```

- Daarmee aangetoond dat het servicefilter `WinRM` in deze omgeving de externe WinRM-toegang verhinderde.
- Firewall bleef ingeschakeld.
- Poort-, interface- en bronadresbeperkingen behouden.

### Parameterconflict bij herhaalde provisioning oplossen

- Nieuwe uitvoering van `vagrant up` bereikte het firewallscript, maar faalde bij het bijwerken van bestaande regels:

```text
Set-NetFirewallRule:
Parameter set cannot be resolved using the specified named parameters.
```

- Oorzaak gevonden in `Set-LabAllowRule`:
  - Dezelfde parameters werden gebruikt voor aanmaken en bijwerken.
  - `Name`, `DisplayName` en `Group` werden samen aan `Set-NetFirewallRule` doorgegeven.
- Updatepad aangepast:
  - Parameters kopiëren met `.Clone()`.
  - `DisplayName` verwijderen uit de updateparameters.
  - `Group` verwijderen uit de updateparameters.
  - `NewDisplayName` gebruiken.
  - `Name` behouden als selectieparameter.
- Aanmaakpad met `New-NetFirewallRule` behouden.
- Bij deze fout werd de eerdere firewallpolicy door het script teruggezet vanuit de back-up.

### Terugkerend WinRM-filter corrigeren

- Bij een volgende poging viel de WinRM-verbinding opnieuw weg:

```text
HTTPClient::KeepAliveDisconnected
An existing connection was forcibly closed by the remote host.
```

- Via SSH vastgesteld dat het servicefilter opnieuw op `WinRM` stond.
- Opgeslagen script gecontroleerd.
- Oorzaak gevonden: de aanroep in het hostbestand bevatte nog:

```powershell
-Service 'WinRM'
```

- Permanente correctie aangebracht:

```powershell
Set-LabAllowRule `
    -Name 'WS2-Managed-WinRM-NAT' `
    -Protocol TCP `
    -LocalPort '5985' `
    -InterfaceAlias $NatInterface `
    -RemoteAddress $NatGateway `
    -Service 'Any'
```

- Opgeslagen inhoud gecontroleerd met:

```powershell
Select-String `
    -Path .\scripts\configure-firewall.ps1 `
    -Pattern "Name 'WS2-Managed-WinRM-NAT'" `
    -Context 0,6
```

- Bevestigd dat het bestand nu `-Service 'Any'` bevat.
- Handmatige correctie op server1 opnieuw toegepast.
- Externe `Test-WSMan` opnieuw succesvol.

### Firewallprovisioning op server1 succesvol afgerond

- `vagrant up` opnieuw gestart.
- Firewallprovisioner op server1 volledig doorlopen.
- Beheerregels behouden:
  - `WS2-Managed-WinRM-NAT`
  - `WS2-Managed-SSH-NAT`
  - `WS2-Managed-SSH-Lab`
- Interne ping- en server1-rolregels ingesteld.
- Rolgebonden AD DS- en DNS-RPC-regels behouden.
- Effectieve firewallprofielen gecontroleerd:

```text
Name    Enabled DefaultInboundAction DefaultOutboundAction
----    ------- -------------------- ---------------------
Domain     True                Block                 Allow
Private    True                Block                 Allow
Public     True                Block                 Allow
```

- Actieve inkomende Allow-regels weergegeven.
- Afsluitende succesmelding ontvangen:

```text
Rolgebonden firewallconfiguratie voltooid voor server1.
```

- Vagrant ging daarna automatisch verder met server2.

### Voortgang van de herbouw om 19:19

| Machine | Laatst bevestigde toestand |
|---|---|
| server1 | Basisrollen eerder ingericht; firewallprovisioning nu succesvol afgerond |
| server2 | Box geïmporteerd, netwerk en portforwarding ingesteld, gestart; wachten op WinRM |
| server3 | In deze herbouw nog niet aan de beurt |
| client | In deze herbouw nog niet aan de beurt |

- Voor server2 automatisch alternatieve hostpoorten toegewezen:
  - RDP: `2200`
  - WinRM HTTP: `2201`
  - WinRM HTTPS: `2202`
  - SSH: `2203`
- Volledige deployment op dit moment nog niet afgerond.
- CA-trigger, server3-provisioning en clientconfiguratie moeten in deze herbouw nog succesvol doorlopen.

***

## Tussenstand op 27 oktober 2026

### Eerder functioneel getest

- Netwerkconfiguratie van de drie servers.
- Active Directory, functional levels, OU’s en gebruikers.
- Primaire en secundaire DNS-configuratie.
- CA-publicatie in Active Directory.
- CA-trust op server1 en de client.
- Web Enrollment via HTTP-redirect en HTTPS.
- CA-bereikbaarheid via `certutil -ping`.
- Intranet-DNS en HTTP-toegang vanaf server1 en client.
- Client-domeinjoin en daaropvolgende CA-verificatie.
- Clientfirewallprofielen.
- SSH-toegang naar alle vier machines zonder de firewall volledig uit te schakelen.
- Websitecertificaathergebruik tijdens herhaalde CA-provisioning.

### Tijdens de huidige herbouw bevestigd

- server1 opnieuw opgebouwd tot domeincontroller.
- OU’s en gebruikers opnieuw aangemaakt.
- Primaire DNS en intranetrecord opnieuw geconfigureerd.
- IIS gecontroleerd met HTTP 200 en gevonden Hello World-inhoud.
- WinRM-firewallprobleem geïdentificeerd en permanent gecorrigeerd.
- Parameterconflict bij updates van firewallregels opgelost.
- Firewallprovisioning van server1 succesvol afgerond.
- Deployment automatisch verdergegaan naar server2.

### Nog te valideren

- Volledige provisioning van server2, server3 en client in de huidige herbouw.
- Automatische uitvoering van de CA-afhankelijke server1-stappen via de server3-trigger.
- Client-domeinjoin zonder afbrekende provisioningfout tijdens een schone deployment.
- CA-trustcontrole op de opnieuw opgebouwde client.
- Controleren dat verificatiescripts na een nieuwe CA-installatie geen oude thumbprint blijven verwachten.
- Exacte RSAT-onderdelen op de opnieuw opgebouwde client.
- Firewall- en SSH-tests op alle vier opnieuw opgebouwde machines.
- Herhaalde uitvoering van de gecorrigeerde firewallprovisioners.
- Volledige schone deployment zonder handmatige herstelstappen, met uitsluitend `vagrant up`.

***

## 2026-10-30 — Scripts en testchecklist verder uitgewerkt

Commit: `ec544748d620cac1733530d797eee1d199caa9e1`.

- Week 6-checklist uitgebreid met automatisering, configuratieopruiming en een volledige uitroltest.
- Scripts voor CA-verificatie, domeinjoin, firewall en rootvertrouwen bijgewerkt.
- Foutafhandeling, herbruikbaarheid, uitvoer en logging verbeterd volgens de commitbeschrijving.
- De volledige uitrol bleef een afzonderlijk te bewijzen test. Aanpassingen aan scripts betekenen niet automatisch dat de schone herbouw al geslaagd was.

***

## 2026-11-01 — Domeinjoin en documentatie bijgewerkt

Commits: `587da1d8648e553a156d909cc21769058256a870` en `290ac9b566b3fdae764c65f73b7090b5ae976fec`.

- Domeinjoinscript uitgebreid met foutafhandeling en DNS-validatie.
- Week 6-checklist bijgewerkt.
- Uitgebreidere controlelijsten toegevoegd en verouderde documentatie vervangen.
- Controlepunten voor de eindtest verder uitgewerkt.

***

## 2026-11-03 — Server3-scripts opgesplitst en opgeslagen

Commit: `86b57f104c90594d16ce1d168fe5897878e29fc6`.

De volgende afzonderlijke scripts voor server3 zijn in deze commit opgenomen:

- `configure-web-enrollment-https.ps1`: certificaataanvraag en HTTPS-binding voor Web Enrollment.
- `dhcp.ps1`: DHCP-installatie, scope en exclusion.
- `join-domain.ps1`: domeinjoin en DNS-instellingen.
- `publish-root-ca.ps1`: publicatie van het publieke rootcertificaat in Active Directory.

De eerdere log bevat al werkzaamheden aan deze onderdelen. Deze datum duidt de commit aan waarin de genoemde bestanden zijn opgeslagen, niet noodzakelijk de eerste implementatiedatum.

***

## 2026-11-04 — Code opgeruimd

Commit: `de4de256036a6b317a8cf222b28047e0d397e7d8`.

- Codestructuur aangepast voor leesbaarheid en onderhoud.
- De commitbeschrijving bevat geen afzonderlijke testresultaten. Deze wijziging wordt daarom niet als bewijs van een volledig geslaagde herbouw geregistreerd.

***

## 2026-11-09 — Testresultaten en deploymentguide bijgewerkt

Commit: `9cd922d6a7324f18ee45f9f2eb3a11140b00a0f7`.

- Testdocumentatie bijgewerkt met geslaagde resultaten voor meerdere controles.
- Gebruikersscript aangepast zodat een wachtwoordwijziging bij de volgende aanmelding niet verplicht is.
- Selectie van de standaardroutes in het domeinjoinscript verbeterd.
- Deploymentguide voor het project toegevoegd.
- Welke tests geslaagd zijn, wordt bepaald door de bijbehorende resultaten; de commitbeschrijving alleen is geen bewijs dat ieder onderdeel opnieuw getest is.

***

## 2026-11-11 — Volledige schone herbouw geslaagd

De bewaarde uitrollog bevat uitvoer van 11 november. Deze herbouw is later in de voorbereiding van de demo opnieuw bekeken. Na het verwijderen van de volledige omgeving is de deployment gestart met:

```powershell
vagrant up
```

De vier VM’s zijn opnieuw geïmporteerd en ingericht. Voor deze geslaagde herbouw waren geen losse herstel- of provisioningopdrachten nodig.

### Server1

- Vast intern adres `192.168.26.10/24` ingesteld en persistentie gecontroleerd.
- Automatische DNS-registratie op NAT uitgeschakeld.
- Nieuw forest en domein `WS26-JD.hogent` aangemaakt.
- Domeinpromotie en herstart voltooid.
- Domein-Administratorwachtwoord ingesteld.
- OU’s Beheer, Medewerkers, Servers en Clients aangemaakt.
- Gebruikers John Doe, Anna Smit, Piet Jansen en Marie Peeters aangemaakt.
- John en Anna toegevoegd aan Domain Admins.
- Primaire DNS-zones gecontroleerd en de reversezone aangemaakt.
- A- en PTR-records voor de drie servers ingesteld.
- NS-records, zoneoverdracht en notify voor server2 ingesteld.
- Intranetrecord aangemaakt naar `192.168.26.10`.
- IIS geïnstalleerd; lokale controle gaf HTTP 200 en de verwachte Hello World-inhoud.
- Firewallprovisioning afgerond.

### Server2

- Vast intern adres `192.168.26.20/24` ingesteld.
- Interne DNS ingesteld op server1.
- Domeinjoin en herstart voltooid.
- DNS-rol geïnstalleerd.
- Secundaire zones aangemaakt voor `WS26-JD.hogent`, `26.168.192.in-addr.arpa` en `_msdcs.WS26-JD.hogent`.
- Voor de drie zones een volledige zoneoverdracht aangevraagd.
- Firewallprovisioning afgerond.
- Het aanmaken van zones en aanvragen van transfers is onderscheiden van de aparte controle of records daadwerkelijk geladen zijn.

### Server3

- Vast intern adres `192.168.26.30/24` ingesteld.
- Domeinjoin en herstart voltooid.
- Enterprise Root CA `WS26-JD-Root-CA` geïnstalleerd; configuratie gaf `ErrorId 0`.
- CA-service gecontroleerd als Running.
- Publiek rootcertificaat geëxporteerd naar `C:\LabCertificates\WS26-JD-Root-CA.cer`.
- Web Enrollment geïnstalleerd en de `/CertSrv`-webapplicatie gecontroleerd.
- DHCP-scope `.100–.200` aangemaakt en geactiveerd, met exclusion `.151–.200`.
- Optie 6 ingesteld op `192.168.26.10` en `192.168.26.20`.
- Optie 15 ingesteld op `WS26-JD.hogent`; geen interne routeroptie toegevoegd.
- Automatische DNS-updates door DHCP uitgeschakeld.
- DHCP gebonden aan de interne interface en in AD geautoriseerd.
- Firewallprovisioning afgerond.
- Publicatie van het rootcertificaat in Active Directory geslaagd.

### Client

- DNS-registratie op beide actieve adapters uitgeschakeld.
- RSAT geïnstalleerd voor AD, DNS, DHCP, groepsbeleid en Certificate Services.
- Clientfirewall geconfigureerd.
- Domeinjoin met de Clients-OU uitgevoerd en de client herstart.
- Daarna de automatische CA-eindfase gestart.

### Definitieve CA-eindfase

De huidige Vagrantfile gebruikt de eigen provisioner `lab-finalize`. De oudere server3-trigger uit de notities van oktober is niet meer de huidige aanpak.

De geslaagde volgorde in de log is:

1. server1: `webserver-template`.
2. server3: `server3-web-https`.
3. server1: `ca-trust-gpo`.
4. server1: `server1-trust-root-ca`.
5. server1: `server1-verify-web-enrollment`.
6. Actueel publiek rootcertificaat via de host naar de client kopiëren.
7. client: `client-verify-ca`.

- Templatepermissies toegepast en gecontroleerd.
- Webservercertificaat ontvangen en aan HTTPS op server3 gekoppeld.
- Trust-GPO aangemaakt en aan de domeinroot gekoppeld.
- Rootvertrouwen op server1 na beleidsvernieuwing bevestigd.
- Web Enrollment vanaf server1 gaf HTTP 302 naar HTTPS en daarna HTTP 200.
- De client bepaalde de verwachte thumbprint uit het overgebrachte referentiecertificaat.
- Rootcertificaat en computerbeleidsopslag op de client gecontroleerd.
- Het clientverificatiescript importeerde zelf geen certificaat.
- Intranetcontrole vanaf de client gaf HTTP 200 en Hello World.

Actuele root-CA-thumbprint van deze herbouw:

```text
E98279E7D2384D86D942C4DC7F69D697A6985F3C
```

Webservercertificaat voor HTTPS op server3:

```text
8FCC1FCB46CF52DAA3F47A0CE48E4A56F5EDEF83
```

Dit zijn verschillende certificaten. Oudere thumbprints in deze log blijven historische gegevens en mogen niet gebruikt worden als actuele referentie.

Afsluitende meldingen:

```text
PASS: verwachte Root-CA aanwezig, beleidsopslag aanwezig en certificaat geldig.
PASS: intranet bereikbaar met HTTP 200 en Hello World.
Automatische CA-naverwerking en clientcontrole geslaagd.
```

### Firewall tijdens deze herbouw

- De drie servers kregen ingeschakelde Domain-, Private- en Public-profielen.
- Standaard inkomend beleid: Block; uitgaand: Allow.
- Rolgebonden regels en afzonderlijke NAT-beheerregels toegepast.
- De client kreeg dezelfde standaard profielacties via het afzonderlijke clientscript.
- Een succesvolle profielcontrole is niet hetzelfde als een volledige beoordeling van alle uitzonderingen. Poorten, adressen, interfaces en waar nodig servicefilters moeten samen beoordeeld worden.

***

## 2026-11-14 — Demovoorbereiding en videomontage

- Opnameplan opgesteld voor een demo van maximaal tien minuten.
- Spreektekst en te tonen codefragmenten uitgewerkt per onderdeel.
- Architectuuroverzicht gemaakt voor de introductie.
- De echte herbouwlog geselecteerd als deploymentbewijs.
- Expliciete nslookup-controles via `192.168.26.10` en `192.168.26.20` waren geslaagd voor forward- en reverse-resolutie. De exacte uitvoeringsdatum van deze afzonderlijke controles is hier niet vastgelegd.
- Voor de DNS-demo een tijdelijk record voorzien, met opruiming na de demonstratie. Een eventuele wachttijd wordt ingekort zonder de overdracht handmatig te forceren en die als automatisch voor te stellen.
- Aanmeldfragmenten met Marie Peeters en John Doe voorbereid, met `whoami` als identiteitscontrole.
- Schermopname en cameravideo beschikbaar voor montage in DaVinci Resolve.
- Opstelling uitgewerkt met de schermopname op V1 en de webcamvideo verkleind op V2.
- Snapping tijdens het monteren opnieuw ingeschakeld.
- Definitieve export, upload naar Panopto en indiening zijn op dit moment nog niet als uitgevoerd bevestigd.

***

## 2026-11-15 — Documentatie nagekeken voor indiening

- Deploymentguide herschreven in kortere, eenvoudigere taal.
- Auteur ingevuld en repositoryadres opgenomen.
- `CLIENT\vagrant` gecorrigeerd naar lokaal account voor Vagrant-beheer; niet meer omschreven als Domain Admin in `CN=Users`.
- Verwijzing naar oude triggers vervangen door de huidige provisioner `lab-finalize`.
- Voor `Get-DhcpServerInDC` expliciete aanmelding met het domein-Administratoraccount beschreven.
- Dynamische SSH-hostpoort laten opzoeken met `vagrant ssh-config server3` in plaats van een vaste poort te veronderstellen.
- Verouderde opmerking dat de schone herbouw nog moest gebeuren bijgewerkt.
- Algemene claims afgezwakt en gekoppeld aan concrete controles en uitrolresultaten.
- Deploymentguide compacter gemaakt zonder de opgenomen onderdelen te verwijderen.
- Statuslog aangevuld met commitgegevens en de latere succesvolle herbouw.

## Laatst bevestigde projectstatus — 15 november 2026

- De schone herbouw van alle vier de VM’s is geslaagd met één `vagrant up`, zonder losse herstelopdrachten tijdens die geslaagde uitrol.
- De automatische CA-eindfase en clientcontrole zijn geslaagd.
- Rootvertrouwen en de beleidsopslag zijn tijdens de eindfase op de client bevestigd.
- Web Enrollment is tijdens de eindfase vanaf server1 gecontroleerd; de clientcontrole testte daarnaast het intranet.
- Forward- en reverse-resolutie via beide DNS-servers zijn afzonderlijk succesvol getest.
- De eerdere GUI- en aanmeldtests blijven afzonderlijke functionele controles. De herbouwlog bewijst niet dat alle GUI-controles na deze herbouw opnieuw interactief uitgevoerd zijn.
- De documentatie is bijgewerkt. PDF-export, definitieve videopublicatie en indiening worden pas als afgerond geregistreerd wanneer ze daadwerkelijk uitgevoerd zijn.