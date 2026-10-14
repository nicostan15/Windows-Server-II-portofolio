# Follow-up — Windows Server II, Deel 1

**Datum:** woensdag 14/10/2026
**Sessie:** 11:08 – 11:56 CEST
**Onderwerp:** server1 promoveren tot domeincontroller (via Vagrant, incl. WinRM-fix) + Forest/Domain functional level + OU-structuur en gebruikers + check definitieve opdrachtversie (Week 2 van planning)

---

## Uitgangspunt

Taken uit de planning:

- [ ] server1 promoveren tot domeincontroller
- [ ] Forest/Domain functional level instellen op Windows Server 2025
- [ ] OU-structuur (minstens 3 OU's) + minstens 4 gebruikers scripten (2x Domain Admin, 2x Domain User)
- [ ] Check definitieve opdrachtversie (verschijnt uiterlijk 11/10) op wijzigingen

Bij aanvang van de sessie meldde de gebruiker dat `vagrant up` voor server1 succesvol was afgerond en dat inloggen via `vagrant ssh` lukte — de promotie tot domeincontroller (script `promote-dc.ps1`, inclusief de eerder opgeloste WinRM-crash na AD-promotie) was dus al volledig geautomatiseerd verlopen zonder manuele tussenkomst.

## Wat is er vandaag gedaan

### 1. Verificatie van de domeincontroller-promotie
Met `Get-ADDomain` en `Get-ADForest` werd bevestigd dat de promotie correct en met de juiste functional levels was verlopen:

| Check | Resultaat |
|---|---|
| DomainMode | Windows2025Domain |
| ForestMode | Windows2025Forest |
| Host-Only IP (Ethernet 2) | 192.168.26.10 |
| NetProfile | WS26-JD.hogent (herkent zichzelf als domeinlid) |
| DNSServer | ::1 / 127.0.0.1 (server1 is zelf primaire DNS-server, dankzij `-InstallDns:$true`) |

Alle waarden kwamen overeen met de vereisten uit de opdracht (forest-naam `WS26-JD.hogent`, forest- en domain functional level Windows Server 2025).

### 2. Deployment guide bijgewerkt
De draft-deployment guide (`readme.pdf`-voorganger) werd aangevuld met:
- De concrete uitrolstappen voor server1 (netwerkconfiguratie + automatische DC-promotie via Vagrant).
- Een tabel "Gebruikers en wachtwoorden" met een rij voor het `vagrant`- en `Administrator`-account.
- Sectie 4 ("Status van het project") volledig ingevuld met wat af is, wat nog niet, en een uitgebreide problemen/oplossingen-tabel — inclusief de eerder opgeloste WinRM-crash, de verkeerde functional-level-parameter (`WinThreshold` i.p.v. `Win2025`), en de orphaned-VM-fout (`VERR_ALREADY_EXISTS`) na een gecrashte `vagrant up`.

### 3. OU-structuur en gebruikers gescript
Nieuw script `create-ous-users.ps1` opgesteld, data-gedreven via twee aanpasbare arrays (`$OUs` en `$Users`), en **idempotent** (meerdere keren uitvoerbaar zonder fouten of duplicaten).

**OU's aangemaakt (4, meer dan het vereiste minimum van 3):**
- Beheer — voor de Domain Admin-accounts
- Medewerkers — voor de gewone Domain Users
- Servers — voorzien voor de computerobjecten van server2/server3 na domain join
- Clients — voorzien voor het computerobject van de Windows 11 client

**Gebruikers aangemaakt (4, zoals vereist: 2x Domain Admin, 2x Domain User):**
- John Doe (`j.doe.adm`) en Anna Smit (`a.smit.adm`) — in OU Beheer, toegevoegd aan de groep Domain Admins via `Add-ADGroupMember`.
- Piet Jansen (`p.jansen`) en Marie Peeters (`m.peeters`) — in OU Medewerkers, geen extra groepslidmaatschap.

Het script werd toegevoegd aan de Vagrantfile als vierde provisioning-stap op server1, na `configure-network.ps1`, `promote-dc.ps1` (met `reboot: true`) en de WinRM-verificatie-inline-provisioner — bewust als laatste stap, aangezien de ActiveDirectory-module pas na de voltooide promotie beschikbaar is.

### 4. Testen: vagrant provision i.p.v. destroy/up
Besproken welk commando nodig is om het nieuwe provisioning-blok te testen op een reeds draaiende, reeds gepromoveerde VM. Omdat enkel een nieuwe `vm.provision`-regel was toegevoegd (geen wijziging aan box, netwerk of resources), volstond:
```powershell
vagrant provision server1
```
Dit herbouwt of herstart de VM niet, en voert enkel de provisioners opnieuw uit. Kanttekening: dit commando draait alle shell-provisioners van server1 opnieuw (ook `configure-network.ps1` en `promote-dc.ps1`), wat in dit geval onschadelijk is dankzij de idempotente opzet van de scripts. Een volledige `vagrant destroy` + `vagrant up` was dus niet nodig.

### 5. Verificatie van OU's en gebruikers
Na het uitvoeren van het script werd alles geverifieerd via `vagrant ssh server1`:

```powershell
Get-ADOrganizationalUnit -Filter * | Select-Object Name, DistinguishedName
Get-ADUser -Filter * -SearchBase "OU=Beheer,DC=WS26-JD,DC=hogent" | Select-Object Name, SamAccountName
Get-ADUser -Filter * -SearchBase "OU=Medewerkers,DC=WS26-JD,DC=hogent" | Select-Object Name, SamAccountName
Get-ADGroupMember -Identity "Domain Admins" | Select-Object Name, SamAccountName
```

**Resultaten:** alle 4 custom OU's aanwezig (naast de automatische OU "Domain Controllers"), John Doe en Anna Smit correct in Beheer, Piet Jansen en Marie Peeters correct in Medewerkers, en de Domain Admins-groep bevat naast het standaard Administrator-account exact j.doe.adm en a.smit.adm.

Extra controle uitgevoerd om te bevestigen dat de twee Domain Users **geen** adminrechten hebben:
```powershell
Get-ADGroupMember -Identity "Domain Admins" | Where-Object {$_.SamAccountName -in @("p.jansen","m.peeters")}
```
Lege output — bevestigt dat Piet Jansen en Marie Peeters correct als pure Domain User zijn geconfigureerd, zonder lidmaatschap van Domain Admins.

### 6. Check definitieve opdrachtversie
Een nieuwe versie van het opdrachtdocument (verschenen zoals aangekondigd ten laatste op 11/10) werd woord voor woord vergeleken met de eerder gebruikte draft. Resultaat: slechts **één inhoudelijke wijziging**, uitsluitend in Deel 2 (SQL Server Failover Cluster) — de SQL Server 2025-ISO wordt niet langer gedownload via Academic Software met een specifieke bestandsnaam/SHA256-hash, maar via een downloadtool die beschikbaar is op Orion, en betreft de Evaluation-versie. Alle onderdelen relevant voor Deel 1 (OU-structuur, gebruikers, netwerk, AD/DNS, CA, IIS, firewall, indienstructuur, deadlines) zijn woordelijk ongewijzigd gebleven.

## Problemen tegengekomen (en oplossingen)

| Probleem | Oorzaak | Oplossing |
|---|---|---|
| Onzekerheid of de opdrachtversie nog kon wijzigen | Het eerder gebruikte document bevatte een expliciete "voorlopige draft"-waarschuwing met uiterste publicatiedatum 11/10 | Nieuwste versie opgehaald en zin-voor-zin vergeleken; enige wijziging zit in Deel 2 (SQL-ISO-downloadbron), geen impact op Deel 1 |
| Twijfel over destroy/up vs. provision om het nieuwe script te testen | Niet duidelijk of een nieuwe provisioner een volledige herbouw van de VM vereist | Bevestigd dat `vagrant provision server1` volstaat zolang er geen wijzigingen zijn aan box/netwerk/resources; `vagrant destroy` is enkel nodig bij VM-configuratiewijzigingen |

## Status einde sessie

server1 is bevestigd correct gepromoveerd tot domeincontroller met forest- en domain functional level Windows Server 2025, volledig geautomatiseerd via `vagrant up server1`. De OU-structuur (4 OU's) en de 4 vereiste gebruikers (2x Domain Admin, 2x Domain User) zijn gescript, idempotent, toegevoegd aan de Vagrantfile-provisioning, en volledig geverifieerd — inclusief de expliciete bevestiging dat de Domain Users geen adminrechten hebben. De definitieve opdrachtversie is gecontroleerd en bevat geen wijzigingen die Deel 1 beïnvloeden. Alle vier items uit Week 2 van de planning kunnen worden afgevinkt.