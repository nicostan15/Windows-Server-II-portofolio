# Status log

Bij te houden tijdens het project: datum, wat je deed, problemen en oplossingen.
Handig als basis voor de reflectie in de deployment guide.

## Voorbeeld

### 2026-09-23
- Repo en mapstructuur opgezet.
- TODO: Vagrantfile van Orion toevoegen.

---

### 2026-09-30
- Host-Only IP-configuratie van server1 (192.168.26.10), server2 (192.168.26.20) en server3
  (192.168.26.30) ingesteld via PowerShell (`New-NetIPAddress`), niet via Vagrant.
- Interface geïdentificeerd met `Get-NetAdapter` + `Get-NetIPConfiguration`: "Ethernet" = NAT
  (niet aanraken), "Ethernet 2" = Host-Only (hier IP instellen).
- Connectiviteit getest met `Test-NetConnection`: gaf eerst TimedOut tussen de servers.
- Probleem: Windows Defender Firewall blokkeert ICMP standaard op alle profielen.
- Oplossing (tijdelijk, enkel ter test): `Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled False`.
  Na uitschakelen: ping geslaagd (RTT 1 ms). Firewall structureel aanpakken is uitgesteld naar
  Week 5 (gerichte inkomende regels i.p.v. volledig uitschakelen).
- Herbruikbaar script gemaakt: `scripts/configure-network.ps1` (parameter `-IPAddress`, idempotent:
  slaat over als het IP al correct staat).
- VirtualBox interne DHCP-server gecontroleerd via `VBoxManage list dhcpservers`: stond al
  uitgeschakeld op het relevante Host-Only netwerk (vermoedelijk dankzij `auto_config: false`
  in de Vagrantfile). Geen verdere actie nodig.
- Script geautomatiseerd via de Vagrantfile (`vm.provision "shell", path: ...`) en getest met
  `vagrant reload --provision`: alle 3 servers krijgen nu automatisch het juiste IP bij uitrol.
- Problemen onderweg: eerst per ongeluk in cmd.exe gewerkt i.p.v. PowerShell (`Get-NetAdapter`
  niet herkend, opgelost met `powershell`), en een afgekapte copy-paste van `New-NetIPAddress`
  op server2 (opgelost door de volledige regel opnieuw te plakken).
- **Status Week 2 (deel 1/2):** Host-Only IP-configuratie en DHCP-check volledig afgerond.

### 2026-10-14
- `vagrant up server1` (incl. `promote-dc.ps1`) succesvol doorlopen zonder crash, en
  `vagrant ssh server1` werkte meteen — bevestigt dat de WinRM-fix uit een eerdere sessie
  (transport op `plaintext` + `basic_auth_only`, hogere retry-limiet/-delay) structureel werkt.
  Voordien crashte `vagrant up` met `WinRM::WinRMAuthorizationError` net na de AD-promotie,
  omdat de standaard WinRM negotiate/NTLM-authenticatie niet meer werkt zodra de server
  domeincontroller wordt.
- Functional levels geverifieerd: `Get-ADDomain` → DomainMode `Windows2025Domain`,
  `Get-ADForest` → ForestMode `Windows2025Forest`. Beide correct op Windows Server 2025.
- Netwerk na promotie geverifieerd: `Get-NetIPConfiguration -InterfaceAlias "Ethernet 2"`
  toont nog steeds 192.168.26.10, en server1 gebruikt zichzelf nu als DNS-server (::1/127.0.0.1)
  dankzij `-InstallDns:$true` bij de promotie.
- Definitieve opdrachtversie (verschenen na 11/10) gecontroleerd tegen de draft: enige wijziging
  zit in Deel 2 (SQL Server ISO nu via een Orion-tool i.p.v. Academic Software, Evaluation-versie
  i.p.v. specifieke ISO+hash). Alles relevant voor Deel 1 (OU's, gebruikers, AD/DNS, CA, IIS,
  firewall, indienstructuur, deadlines) ongewijzigd.
- Script gemaakt: `scripts/server1/create-ous-users.ps1` — idempotent, data-gedreven via
  arrays ($OUs, $Users), maakt 4 OU's aan (Beheer, Medewerkers, Servers, Clients; vereiste is
  minstens 3) en 4 gebruikers (2x Domain Admin via lidmaatschap van de groep "Domain Admins",
  2x Domain User zonder extra rechten; vereiste is minstens 2+2).
- Toegevoegd aan de Vagrantfile als laatste provisioning-stap van server1, na `promote-dc.ps1`
  (moet na de promotie draaien, want de ActiveDirectory-module is pas dan beschikbaar).
- Getest met `vagrant provision server1` i.p.v. een volledige destroy/up-cyclus — want enkel
  een nieuwe provisioner toegevoegd, geen wijziging aan box/netwerk/resources.
- Volledige verificatie na provisioning:
  - `Get-ADOrganizationalUnit -Filter *` → Beheer, Medewerkers, Servers, Clients aanwezig.
  - `Get-ADUser -SearchBase "OU=Beheer,..."` → John Doe (j.doe.adm), Anna Smit (a.smit.adm).
  - `Get-ADUser -SearchBase "OU=Medewerkers,..."` → Piet Jansen (p.jansen), Marie Peeters (m.peeters).
  - `Get-ADGroupMember -Identity "Domain Admins"` → Administrator, j.doe.adm, a.smit.adm.
  - Expliciet gecontroleerd dat p.jansen/m.peeters **niet** in Domain Admins zitten → lege
    output, bevestigd correct.
- **Status Week 2 (deel 2/2):** server1 promoveren tot DC, functional levels, OU-structuur +
  gebruikers, en check van de definitieve opdrachtversie — alle vier volledig afgerond.