# Status log

Bijgehouden tijdens het project: datum, uitgevoerde werk, problemen en oplossingen.

### 2026-09-23

- Repo en mapstructuur opgezet.
- TODO: Vagrantfile van Orion toevoegen.

---

### 2026-09-30

- Host-Only IP-configuratie van server1 (`192.168.26.10`), server2 (`192.168.26.20`) en server3 (`192.168.26.30`) ingesteld via PowerShell.
- Interface geïdentificeerd met `Get-NetAdapter` en `Get-NetIPConfiguration`.
- Connectiviteit getest met `Test-NetConnection`.
- Windows Defender Firewall blokkeerde ICMP; tijdelijk uitgeschakeld voor testen.
- Herbruikbaar script gemaakt: `scripts/configure-network.ps1`.
- VirtualBox-interne DHCP-server gecontroleerd en bevestigd uitgeschakeld.
- Netwerkconfiguratie geautomatiseerd via Vagrant provisioning.
- **Status Week 2, deel 1/2:** Host-Only IP-configuratie en DHCP-check volledig afgerond.

---

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

---

### 2026-10-20 — DNS-automatisatie en herhaalbaarheid

- Primaire DNS-script uitgebreid met DNS-firewallregels en NS-/transferinstellingen.
- Parameterconflict in het firewallblok opgelost.
- `dns-primary` en `dns-secondary` elk tweemaal succesvol uitgevoerd.
- Na herprovisioning op server2 bevestigd dat alle drie labzones Secondary zijn.
- A- en PTR-records van server1, server2 en server3 gecontroleerd.
- Geen NAT-IP aanwezig in de gecontroleerde A-records.
- DNS-configuratie en herhaalde provisioning geverifieerd.

---

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
