# Planning Windows Server II — Deel 1 (Automatisatie basisdiensten)

**Start:** 24/09/2026 · **Deadline indienen:** zondag 15/11/2026, 15:00
**Vuistregel uit de opdracht:** scripts + omgeving werkend tegen **08/11**, zodat de laatste week vrij is voor de demo-video (max. 10 min, webcam + micro verplicht, delen via Panopto met beide lectoren).

De definitieve opdrachtversie is gecontroleerd op wijzigingen.
De gebruikte Vagrant-boxen zijn lokaal gedownload.

---

## Week 1 — 28/09 t/m 04/10: Setup & voorbereiding

- [x] VirtualBox 7.2.x en Vagrant installeren (`winget install Hashicorp.Vagrant` of Linux-equivalent)
- [x] Basis-`Vagrantfile` van Orion downloaden
- [x] **Belangrijk:** Vagrant boxes lokaal downloaden/cachen vóór 1 oktober:
  - `gusztavvargadr/windows-server-2025-standard-core` (2607.0.0)
  - `gusztavvargadr/windows-11-25h2-enterprise` (2607.1.0)
- [x] Alle 4 VMs één keer opstarten (`vagrant up`) om te testen of alles werkt
- [x] Netwerktopologie doornemen: NAT-interface + Host-Only (192.168.26.0/24)
- [x] Windows Server I-cursus (AD, DNS, DHCP) herbekijken als opfrissing
- [x] Mapje/repo structuur opzetten (`scripts/`, git init voor versiebeheer)

## Week 2 — 05/10 t/m 11/10: Netwerk & Active Directory

- [x] Host-Only IP-configuratie via PowerShell instellen (niet via Vagrant):
  - server1: 192.168.26.10, server2: 192.168.26.20, server3: 192.168.26.30
- [x] VirtualBox interne DHCP-server uitschakelen (client moet IP via Windows DHCP krijgen)
- [x] server1 promoveren tot domeincontroller (domeinnaam `WS26-$initialen.hogent`)
- [x] Forest/Domain functional level instellen op Windows Server 2025
- [x] OU-structuur (minstens 3 OU's) + minstens 4 gebruikers scripten (2x Domain Admin, 2x Domain User)
- [x] Check definitieve opdrachtversie (verschijnt uiterlijk 11/10) op wijzigingen

## Week 3 — 12/10 t/m 18/10: DNS

- [x] Primaire DNS-rol op server1, forward + reverse lookup zone
- [x] A-records en PTR-records voor de 3 servers (enkel host-only IP, niet NAT!)
- [x] server2 instellen als secundaire DNS-server
- [x] Zone transfers testen (tijdelijk CNAME-record aanmaken op primaire DNS en verificeren op secundaire)
- [x] Voorkomen dat client en NAT-interfaces zichzelf registreren in DNS
- [x] Alles scripten in herbruikbare PowerShell-scripts (niet manueel herhalen!)

## Week 4 — 19/10 t/m 25/10: DHCP & Certification Authority

- [x] DHCP-rol installeren op server3
- [x] Scope instellen: 192.168.26.100–200 (151–200 nog niet gebruiken)
- [x] DHCP-opties ingesteld:
  - Optie 6: DNS-servers `192.168.26.10` en `192.168.26.20`.
  - Optie 15: DNS-domeinnaam `WS26-JD.hogent`.
  - De domeinjoin blijft een afzonderlijke stap.
- [x] Certification Authority installeren op server3
- [x] GPO maken zodat CA automatisch vertrouwd wordt door alle domeinleden
- [x] Web Enrollment Role Service testen via `http://FQDN/CertSrv`

## Week 5 — 26/10 t/m 01/11: IIS, Management Tools & Firewall

- [x] IIS installeren op server1, statische "Hello World"-pagina op poort 80
- [x] DNS-record voor `http://intranet.$jouw-domein` toevoegen en testen
- [x] RSAT-tools automatisch installeren op de Windows 11 client (enkel wat nodig is voor de demo)
- [x] Firewallregels per server scripten (enkel noodzakelijk inkomend verkeer toelaten + correcte default policy)
  - [x] Firewall ingeschakeld en correcte default policy toegepast
  - [x] Eerste aanscherping per server uitgevoerd en functioneel getest
  - [x] Overblijvende uitzonderingen en beheerregels minimaliseren
  - [x] Firewallconfiguratie automatisch in de normale provisioning toepassen
- [x] Testen of `vagrant ssh` werkt zonder firewall volledig uit te schakelen in de finale scripts

## Week 6 — 02/11 t/m 08/11: Automatiseren, testen & afwerken scripts

- [x] Server2 automatisch aan het domein toevoegen en controleren
- [x] Root-CA-vertrouwen controleren op alle vier de machines
- [x] Volledige omgeving vanaf nul opnieuw uitrollen met je scripts (test herhaalbaarheid!)
- [x] Scripts namen regelen, consitente benaming.
- [x] Scripts inhoud onnodige zaken weglaten
- [x] Waar mogelijk: scripts laten uitvoeren via Vagrant/Packer i.p.v. manueel (nice-to-have, geen must)
- [x] Alle scripts opkuisen, herbruikbaar maken (gebruikers/OU's makkelijk aanpasbaar)
- [x] Bugs/edge cases oplossen (bv. shared folder niet beschikbaar na domain join → scripts lokaal kopiëren)
- Oorspronkelijk doel: scripts en omgeving werkend tegen 08/11.
- [x] Volledige schone herbouw succesvol afgerond op 11/11.

## Week 7 — 09/11 t/m 15/11: Documentatie, video & indienen

- [x] Deployment guide schrijven (`readme.pdf`, max. 8 pagina's): stappenplan (dummy-proof), gebruikers + wachtwoorden, status/reflectie, conclusie
- [x] Demo-video opnemen (max. 10 min, webcam + micro verplicht):
  - ±6 min: uitrol via scripts + korte uitleg per script
  - ±4 min: demo van de diensten (AD, DNS zone transfer, DHCP, CA, IIS)
- [x] Video pauzeren tijdens lange uitrol-stappen om onder 10 minuten te blijven
- [x] Video uploaden naar Panopto en delen met jeroen.courtens@hogent.be en pieterjan.maenhaut@hogent.be
- [x] ZIP samenstellen: `WS2-2627-EP1-NaamVoornaam.zip` met `readme.pdf`, `demo.txt` (link naar video), map `scripts/`
- [x] Controleren: ZIP max. 5 MB (geen ISO's, `.vagrant`-folder, installers meenemen)
- [x] **Indienen via Orion vóór zondag 15/11/2026, 15:00** — niet wachten tot het laatste moment!

---

## Checklist vereisten (voor eigen controle)

| Onderdeel | Vereiste |
|---|---|
| VMs | server1 (AD/DNS-primair/IIS), server2 (DNS-secundair), server3 (CA/DHCP), client (Win11 + RSAT) |
| Domein | `WS26-$initialen.hogent`, forest/domain level = Server 2025 |
| OU's & gebruikers | ≥3 OU's, ≥2 Domain Admin, ≥2 Domain User |
| DNS | forward + reverse zone, A + PTR per server, zone transfer werkend |
| DHCP | scope 192.168.26.100–200, opties correct, VirtualBox-DHCP uit |
| CA | vertrouwd via GPO, Web Enrollment werkend |
| IIS | Hello World via `http://intranet.$domein` |
| Firewall | enkel noodzakelijke inkomende regels + correcte default policy |
| Indiening | ZIP ≤5MB, `readme.pdf` (≤8p), `demo.txt`, `scripts/` |
