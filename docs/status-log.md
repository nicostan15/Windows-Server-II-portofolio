# Status log


Bijgehouden tijdens het project: datum, uitgevoerde werk, problemen en oplossingen.


### 2026-09-23


- Repo en mapstructuur opgezet.
- TODO: Vagrantfile van Orion toevoegen.


***


### 2026-09-30


- Host-Only IP-configuratie van server1 (`192.168.26.10`), server2 (`192.168.26.20`) en server3 (`192.168.26.30`) ingesteld via PowerShell.
- Interface geïdentificeerd met `Get-NetAdapter` en `Get-NetIPConfiguration`.
- Connectiviteit getest met `Test-NetConnection`.
- Windows Defender Firewall blokkeerde ICMP; tijdelijk uitgeschakeld voor testen.
- Herbruikbaar script gemaakt: `scripts/configure-network.ps1`.
- VirtualBox-interne DHCP-server gecontroleerd en bevestigd uitgeschakeld.
- Netwerkconfiguratie geautomatiseerd via Vagrant provisioning.
- **Status Week 2, deel 1/2:** Host-Only IP-configuratie en DHCP-check volledig afgerond.


***


### 2026-10-14


- `vagrant up server1` succesvol doorlopen, inclusief AD-promotie en herstart.
- WinRM-fix bevestigd: transport `plaintext`, `basic_auth_only = true` en verhoogde retry-instellingen.
- Functional levels geverifieerd als `Windows2025Domain` en `Windows2025Forest`.
- Netwerkconfiguratie na promotie gecontroleerd.
- Definitieve opdrachtversie gecontroleerd tegen de draft.
- Script gemaakt: `scripts/server1/create-ous-users.ps1`.
- Vier OU’s en vier gebruikers geautomatiseerd aangemaakt.
- Gebruikers lidmaatschappen gecontroleerd: twee Domain Admins en twee Domain Users.
- **Status Week 2, deel 2/2:** server1 promoveren tot DC, functional levels, OU-structuur en gebruikers volledig afgerond.


***


### 2026-10-20 — DNS-automatisatie en herhaalbaarheid


- Primaire DNS-script uitgebreid met DNS-firewallregels en NS-/transferinstellingen.
- Parameterconflict in het firewallblok opgelost.
- `dns-primary` en `dns-secondary` elk tweemaal succesvol uitgevoerd.
- Na herprovisioning op server2 bevestigd dat alle drie labzones Secondary zijn.
- A- en PTR-records van server1, server2 en server3 gecontroleerd.
- Geen NAT-IP aanwezig in de gecontroleerde A-records.
- DNS-configuratie en herhaalde provisioning geverifieerd.


***


### 2026-10-21 — Enterprise Root CA, Web Enrollment en automatische verificatie


- `scripts/server3/03-ca.ps1` uitgebreid en uitgevoerd voor de installatie en configuratie van Active Directory Certificate Services op server3.
- Enterprise Root CA `WS26-JD-Root-CA` geïnstalleerd en geconfigureerd.
- CA-service `CertSvc` gecontroleerd en actief bevonden.
- Publiek CA-rootcertificaat geëxporteerd naar `C:\LabCertificates\WS26-JD-Root-CA.cer`.
- Certificaatdetails gecontroleerd: subject, issuer, thumbprint en geldigheidsperiode.
- CA Web Enrollment-rol geïnstalleerd.
- `/CertSrv`-webapplicatie gecontroleerd in IIS.
- Websitecertificaat voor `server3.WS26-JD.hogent` aangevraagd bij de eigen Enterprise Root CA.
- Certificaat gecontroleerd op subject, issuer, private key en geldigheid.
- HTTPS-binding op poort 443 geconfigureerd in IIS.
- HTTPS-toegang tot `/CertSrv` getest met domeincredentials; resultaat was HTTP 200.
- Directe HTTP-toegang tot `/CertSrv` gaf aanvankelijk HTTP `403.4`, omdat de Certificate Services-pagina HTTPS vereist.
- Aparte IIS-redirectsite toegevoegd voor de HTTP-ingang.
- HTTP-redirect geconfigureerd met status `302 Found` naar `https://server3.WS26-JD.hogent/certsrv/Default.asp`.
- Redirectsite expliciet ingesteld op anonieme toegang, zonder Windows-authenticatie en zonder SSL-vereiste.
- Bestaande HTTPS-site en HTTPS-certificaatbinding ongewijzigd gelaten.
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
HTTP-redirect: 302 naar https://server3.WS26-JD.hogent/certsrv/Default.asp
HTTPS-pagina: HTTP 200
Paginatitel: Microsoft Active Directory Certificate Services
```


- Checklistpunt afgerond:


```markdown
- [x] Web Enrollment Role Service testen via http://FQDN/CertSrv
```


- Openstaand opvolgpunt genoteerd: het CA-script vraagt bij herhaalde provisioning nog steeds een nieuw websitecertificaat aan. De bestaande configuratie werkt correct, maar certificaathergebruik moet nog worden toegevoegd voor volledige idempotentie.


***


### 2026-10-22 — Automatische CA-trust via Active Directory en GPO


- Nieuw script gemaakt: `scripts/server3/06-publish-root-ca.ps1`.
- Het script publiceert het publieke rootcertificaat van `WS26-JD-Root-CA` automatisch in Active Directory.
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
- Het script controleert herhaaldelijk of server1 het rootcertificaat automatisch in de Trusted Root-store heeft ontvangen.
- Verificatie uitgevoerd met:


```powershell
vagrant provision server1 --provision-with server1-trust-root-ca
```


- Rootcertificaat bevestigd op server1:


```text
Subject: CN=WS26-JD-Root-CA, DC=WS26-JD, DC=hogent
Thumbprint: 9BAC7EC5CC2A09C9CC23A8494366AF26248C288B
NotAfter: 10/21/2031 6:44:30 PM
```


- Bestaand script `scripts/server1/configure-ca-trust-gpo.ps1` uitgevoerd.
- GPO `WS26 - Vertrouw Root CA` aangemaakt en gekoppeld aan het domein `DC=WS26-JD,DC=hogent`.
- De GPO distribueert het rootcertificaat automatisch naar alle domeinleden via de Trusted Root policy store.
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
- Web Enrollment opnieuw gecontroleerd nadat de GPO was toegepast.
- HTTP-ingang gaf opnieuw een `302`-redirect naar HTTPS.
- HTTPS-pagina gaf `HTTP 200` met paginatitel `Microsoft Active Directory Certificate Services`.
- De volledige CA-keten is nu geautomatiseerd: publicatie in Active Directory, automatische trust via GPO en automatische verificatie van Web Enrollment.
- Checklistpunt afgerond:


```markdown
- [x] GPO maken zodat CA automatisch vertrouwd wordt door alle domeinleden
```


- **Status Week 4:** DHCP, Certification Authority, automatische CA-trust via GPO en Web Enrollment volledig afgerond.

### 2026-10-26 — IIS, client-domeinjoin, firewall en volledige provisioning-automatisatie

- Root-CA-publicatie in Active Directory opnieuw uitgevoerd na correctie van `scripts/server3/06-publish-root-ca.ps1`.
- Het publicatiescript aangepast zodat de `certutil -dspublish`-opdracht via `cmd.exe` wordt uitgevoerd met een betrouwbare logomleiding.
- Publicatie succesvol gecontroleerd:

```text
Certificate already in DS store.
CertUtil: -dsPublish command completed successfully.
Root-CA-certificaat is gepubliceerd in Active Directory.
```

- Webserver-certificaattemplate geconfigureerd via `webserver-template`.
- Expliciete Enroll-rechten gecontroleerd voor de domein-Administrator en de webserver-identiteit.
- GPO `WS26 - Vertrouw Root CA` opnieuw aangemaakt, gekoppeld aan het domein en geverifieerd.
- Root-CA-certificaat op server1 bevestigd in `Cert:\LocalMachine\Root`:

```text
Subject: CN=WS26-JD-Root-CA, DC=WS26-JD, DC=hogent
Thumbprint: 226C58F452BB9970BD08435929CCEF1DE44670F7
NotAfter: 10/26/2031
```

- Web Enrollment opnieuw gecontroleerd vanaf server1:

```text
HTTP-ingang: http://server3.WS26-JD.hogent/CertSrv/
HTTP-redirect: 302 naar [https://server3.WS26-JD.hogent/certsrv/Default.asp](https://server3.WS26-JD.hogent/certsrv/Default.asp)
HTTPS-pagina: HTTP 200
```

- CA-bereikbaarheid getest vanaf server1:

```powershell
certutil -ping -config "server3.WS26-JD.hogent\WS26-JD-Root-CA"
```

- Resultaat bevestigd:

```text
Server "WS26-JD-Root-CA" ICertRequest2 interface is alive.
CertUtil: -ping command completed successfully.
```

- IIS op server1 gecontroleerd: `intranet.WS26-JD.hogent` resolveert naar `192.168.26.10` en geeft HTTP `200 OK`.
- Windows 11-client uitgebreid met RSAT via `scripts/client/02-install-rsat.ps1`.
- Client toegevoegd aan het domein `WS26-JD.hogent` via nieuw script `scripts/client/04-join-domain.ps1`.
- Domeinjoin geautomatiseerd in de Vagrantfile als provisioner `client-domain`, met automatische herstart.
- Na de domeinjoin Group Policy vernieuwd en de Root-CA-trust op de client gecontroleerd.
- Rootcertificaat bevestigd op de client in `Cert:\LocalMachine\Root`.
- Toegang tot het intranet vanaf de client bevestigd met HTTP `200 OK`.
- Nieuw verificatiescript gemaakt: `scripts/client/03-verify-ca.ps1`.
- Verificatiescript toegevoegd als provisioner `client-verify-ca` met `run: "always"`.
- Firewall op de client geconfigureerd via nieuw script `scripts/client/configure-client-firewall.ps1`.
- Firewallprofielen Domain, Private en Public ingeschakeld met:

```text
DefaultInboundAction  : Block
DefaultOutboundAction : Allow
```

- Enkel noodzakelijke regels ingeschakeld: Core Networking en WinRM.
- SSH-toegang behouden via de bestaande firewallregel `OpenSSH-Server-In-TCP`.
- `vagrant ssh` getest op server1, server2, server3 en client met actieve firewall.
- SSH-regel op alle vier machines gecontroleerd:

```text
Name                  Enabled Direction Action
----                  ------- --------- ------
OpenSSH-Server-In-TCP    True   Inbound  Allow
```

- Vagrantfile aangepast voor volledige automatisering:
  - `server3-publish-root-ca` ingesteld op `run: "always"`.
  - CA-afhankelijke server1-provisioners ingesteld op `run: "never"` en automatisch aangeroepen via een `trigger.after :up` op server3.
  - Trigger voert uit: `webserver-template`, `ca-trust-gpo`, `server1-verify-web-enrollment` en `server1-trust-root-ca`.
  - Clientvolgorde vastgelegd als: firewall, RSAT, domeinjoin met herstart, daarna CA-verificatie.
- Hierdoor kan de volledige omgeving opnieuw worden opgebouwd met enkel `vagrant up`.
- Checklistpunten afgerond:

```markdown
- [x] IIS installeren op server1, statische "Hello World"-pagina op poort 80
- [x] DNS-record voor http://intranet.$jouw-domein toevoegen en testen
- [x] RSAT-tools automatisch installeren op de Windows 11 client
- [x] Firewallregels per server scripten
- [x] Firewall ingeschakeld en correcte default policy toegepast
- [x] Eerste aanscherping per server uitgevoerd en functioneel getest
- [x] Overblijvende uitzonderingen en beheerregels minimaliseren
- [x] Firewallconfiguratie automatisch in de normale provisioning toepassen
- [x] Testen of `vagrant ssh` werkt zonder firewall volledig uit te schakelen
```

- **Status Week 5:** IIS, intranet-DNS, RSAT, client-domeinjoin, automatische CA-trust op de client, firewallbeleid en SSH-toegang volledig afgerond en geautomatiseerd.