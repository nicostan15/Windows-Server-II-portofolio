# Follow-up — Windows Server II, Deel 1

Datum: woensdag 14/10/2026  
Sessies: 11:08 – 11:56 CEST en 14:48 – 15:30 CEST  
Onderwerp: domeincontroller-promotie en functional levels, OU-structuur en gebruikers, controle opdrachtversie, primaire DNS-configuratie en troubleshooting

---

## Uitgangspunt

Taken uit de planning:

- [ ] server1 promoveren tot domeincontroller
- [ ] Forest/Domain functional level instellen op Windows Server 2025
- [ ] OU-structuur (minstens 3 OU's) + minstens 4 gebruikers scripten (2x Domain Admin, 2x Domain User)
- [ ] Check definitieve opdrachtversie op wijzigingen
- [ ] Primaire DNS-rol op server1, forward + reverse lookup zone

De Host-Only IP-configuratie was tijdens een eerdere sessie al ingesteld en geautomatiseerd:

| VM | Host-Only IP |
|---|---|
| server1 | 192.168.26.10 |
| server2 | 192.168.26.20 |
| server3 | 192.168.26.30 |

Bij aanvang van de ochtendsessie was `vagrant up server1` succesvol afgerond en lukte inloggen via `vagrant ssh server1`. De domeincontroller-promotie via `promote-dc.ps1`, inclusief de eerder aangepaste WinRM-configuratie, was dus succesvol verlopen.

## Wat is er vandaag gedaan

### 1. Domeincontroller-promotie en functional levels geverifieerd

Op server1 werden de domein-, forest- en netwerkgegevens gecontroleerd:

```powershell
Get-ADDomain | Select-Object Name, DomainMode
Get-ADForest | Select-Object Name, ForestMode
Get-NetIPConfiguration -InterfaceAlias "Ethernet 2"
```

| Check | Resultaat |
|---|---|
| Domeinnaam | WS26-JD |
| Forest-naam | WS26-JD.hogent |
| DomainMode | Windows2025Domain |
| ForestMode | Windows2025Forest |
| Host-Only IP | 192.168.26.10 |
| NetProfile.Name | WS26-JD.hogent |
| Geconfigureerde DNS-adressen | ::1 en 127.0.0.1 |

De functional levels stonden correct op Windows Server 2025. Het Host-Only IP bleef behouden na de promotie en reboot.

De eerder gebruikte WinRM-aanpassing bleef in de Vagrantfile behouden:

```ruby
config.winrm.transport = :plaintext
config.winrm.basic_auth_only = true
config.winrm.retry_limit = 60
config.winrm.retry_delay = 10
```

De succesvolle uitrol bevestigde dat deze aanpassing in de huidige labomgeving de eerder opgetreden WinRM-authenticatiefout na promotie omzeilde.

### 2. Deployment guide bijgewerkt

De draft-deployment guide werd aangevuld met:

- Uitrolstappen voor server1: netwerkconfiguratie, domeincontroller-promotie en reboot.
- Verificatiecommando's voor functional levels en netwerkconfiguratie.
- Een voorlopig overzicht van accounts en wachtwoorden.
- Projectstatus en openstaande onderdelen.
- Eerder besproken problemen en oplossingen, waaronder de WinRM-crash, functional-level-parameters en een verweesde VirtualBox-VM-map.

Aandachtspunt: de guide moet verder worden bijgewerkt met de nieuwe OU-/gebruikersstap en de definitieve DNS-configuratie. Alleen aantoonbaar geteste resultaten mogen als afgerond worden vermeld.

### 3. OU-structuur en gebruikers gescript

Nieuw script opgesteld:

```text
scripts/server1/create-ous-users.ps1
```

De configuratie gebruikt twee aanpasbare arrays:

- `$OUs`: namen van de aan te maken OU's.
- `$Users`: gebruikersgegevens, doel-OU en rol.

Het script controleert of OU's, gebruikers en groepslidmaatschappen al bestaan voordat het nieuwe objecten toevoegt.

#### OU-structuur

| OU | Doel |
|---|---|
| Beheer | Domain Admin-accounts |
| Medewerkers | Gewone gebruikers |
| Servers | Voorzien voor server2/server3 na domain join |
| Clients | Voorzien voor de Windows 11-client na domain join |

Er werden vier eigen OU's aangemaakt, naast de bestaande OU `Domain Controllers`.

#### Gebruikers

| Naam | Account | OU | Gewenste rol |
|---|---|---|---|
| John Doe | j.doe.adm | Beheer | Domain Admin |
| Anna Smit | a.smit.adm | Beheer | Domain Admin |
| Piet Jansen | p.jansen | Medewerkers | Domain User |
| Marie Peeters | m.peeters | Medewerkers | Domain User |

John Doe en Anna Smit werden via `Add-ADGroupMember` toegevoegd aan `Domain Admins`.

### 4. OU-/gebruikersscript toegevoegd aan Vagrant

De volgende provisioningregel werd toegevoegd binnen het server1-blok:

```ruby
server1.vm.provision "shell",
  path: "scripts/server1/create-ous-users.ps1"
```

De bedoelde uitvoervolgorde:

1. `configure-network.ps1`
2. `promote-dc.ps1` met `reboot: true`
3. Inline WinRM-verificatie
4. `create-ous-users.ps1`
5. Later toegevoegd: `configure-dns-server1.ps1`

Voor het testen op de bestaande VM was geen destroy/up-cyclus nodig.

Belangrijke correctie op het eerdere advies: `vagrant provision server1` draait alle geselecteerde provisioners opnieuw. In deze Vagrantfile kan dat wel degelijk een reboot veroorzaken, omdat de promotie-provisioner `reboot: true` bevat. Dit werd tijdens de namiddagsessie zichtbaar in de Vagrant-output, ook wanneer het promotiescript zelf meldde dat geen actie nodig was.

### 5. OU's en gebruikers geverifieerd

Op server1 uitgevoerd:

```powershell
Get-ADOrganizationalUnit -Filter * |
    Select-Object Name, DistinguishedName

Get-ADUser -Filter * `
    -SearchBase "OU=Beheer,DC=WS26-JD,DC=hogent" |
    Select-Object Name, SamAccountName

Get-ADUser -Filter * `
    -SearchBase "OU=Medewerkers,DC=WS26-JD,DC=hogent" |
    Select-Object Name, SamAccountName

Get-ADGroupMember -Identity "Domain Admins" |
    Select-Object Name, SamAccountName
```

Resultaten:

- Beheer, Medewerkers, Servers en Clients aanwezig.
- John Doe en Anna Smit aanwezig in Beheer.
- Piet Jansen en Marie Peeters aanwezig in Medewerkers.
- Domain Admins bevatte Administrator, j.doe.adm en a.smit.adm.

Aanvullende controle:

```powershell
Get-ADGroupMember -Identity "Domain Admins" |
    Where-Object {
        $_.SamAccountName -in @("p.jansen", "m.peeters")
    }
```

Deze controle gaf lege output.

Dit bevestigt dat Piet Jansen en Marie Peeters geen directe leden zijn van Domain Admins. Het is op zichzelf geen volledige controle van alle mogelijke administratorrechten of indirecte groepslidmaatschappen.

### 6. Opdrachtversies gecontroleerd

De opnieuw aangeleverde opdracht-PDF werd naast de eerder gebruikte draft gelegd.

Vastgestelde verschillen:

- De voorlopige-draftmelding was verdwenen.
- Bij Deel 2 stond nu SQL Server 2025 Evaluation, te downloaden via een tool op Orion.
- De eerdere verwijzing naar Academic Software, een specifieke ISO-bestandsnaam en SHA256-hash was daar niet meer opgenomen.

In de geraadpleegde onderdelen van Deel 1 werden geen relevante wijzigingen vastgesteld. De OU-/gebruikerseisen bleven minstens drie OU's en vier gebruikers, waarvan twee Domain Admins en twee gewone Domain Users.

De exacte publicatiedatum en een formeel versienummer van de nieuwe PDF werden niet afzonderlijk bevestigd.

### 7. Primaire DNS-configuratie gescript

Nieuw script opgesteld en opgeslagen in:

```text
scripts/server1/configure-dns-server1.ps1
```

De bestaande AD-forward zone werd gebruikt:

```text
WS26-JD.hogent
```

De reverse lookup zone voor het Host-Only netwerk werd toegevoegd:

```text
26.168.192.in-addr.arpa
```

De gewenste serverrecords:

| Server | A-record | PTR-doel |
|---|---|---|
| server1 | 192.168.26.10 | server1.WS26-JD.hogent. |
| server2 | 192.168.26.20 | server2.WS26-JD.hogent. |
| server3 | 192.168.26.30 | server3.WS26-JD.hogent. |

Daarnaast werd de configuratie voorbereid op server2 als secundaire DNS-server:

- NS-record voor server2 in de forward en reverse zone.
- Zone transfers beperkt tot 192.168.26.20.
- Notify ingesteld voor server2.

Deze voorbereiding betekent nog niet dat secundaire DNS en zone transfers al werkend zijn getest.

### 8. Eerste DNS-verificatie: NAT-records en ontbrekend PTR-record

De DNS-service draaide en beide zones waren aanwezig:

```powershell
Get-Service DNS

Get-DnsServerZone |
    Select-Object ZoneName, ZoneType,
        IsDsIntegrated, IsReverseLookupZone
```

De eerste controle van de records toonde echter twee fouten:

1. Het NAT-IP `10.0.2.15` stond nog als A-record bij:
   - `@`
   - `DomainDnsZones`
   - `ForestDnsZones`
   - `server1`

2. PTR-record `10` voor server1 ontbrak.

Forward lookup van server1 gaf daardoor twee adressen terug:

```text
192.168.26.10
10.0.2.15
```

Reverse lookup van `192.168.26.10` gaf:

```text
DNS name does not exist
```

De interfacecontrole toonde ondertussen:

| Interface | RegisterThisConnectionsAddress |
|---|---|
| Ethernet (NAT) | False |
| Ethernet 2 (Host-Only) | True |

De NAT-clientregistratie was dus al uitgeschakeld, maar bestaande NAT-records waren nog aanwezig.

### 9. DNS-fouten manueel hersteld

De A-records met exact het NAT-IP `10.0.2.15` werden geselecteerd en gericht verwijderd. De records met het Host-Only IP bleven behouden.

Het ontbrekende PTR-record werd afzonderlijk aangemaakt:

```powershell
Add-DnsServerResourceRecordPtr `
    -ZoneName "26.168.192.in-addr.arpa" `
    -Name "10" `
    -PtrDomainName "server1.WS26-JD.hogent."
```

De DNS-luisterinterface werd beperkt tot het Host-Only IP:

```powershell
dnscmd localhost /ResetListenAddresses 192.168.26.10
Restart-Service DNS
```

Na de reparatie toonden de controles:

- Geen NAT-IP meer in de getoonde A-records van de domeinzone.
- PTR-records 10, 20 en 30 aanwezig.
- Forward lookup van server1 gaf uitsluitend 192.168.26.10.
- Reverse lookup van 192.168.26.10 gaf server1.WS26-JD.hogent.

### 10. DNS-script verbeterd voor automatische heruitrol

De manuele reparaties werden verwerkt in het script.

Belangrijkste aanpassingen:

- `$ErrorActionPreference = "Stop"` om onverwachte fouten niet te negeren.
- Controle van DNS-rol en bestaande AD-forward zone.
- NAT-interface identificeren via de default gateway.
- DNS-clientregistratie op de NAT-interface uitschakelen.
- DNS laten luisteren op 192.168.26.10.
- A-records met de huidige NAT-IP-adressen opruimen in lokale primaire forward zones.
- Reverse zone aanmaken indien die ontbreekt.
- A-records en PTR-records onafhankelijk controleren.
- Verkeerde A-/PTR-doelen voor de beheerde serverrecords gericht verwijderen.
- Zone transfers expliciet beperken tot server2.

De oorspronkelijke fout zat in deze logica:

```text
A-record bestaat al → zowel A- als PTR-aanmaak overslaan
```

De aangepaste logica:

```text
A-record controleren/herstellen
PTR-record afzonderlijk controleren/herstellen
```

Hierdoor kan een ontbrekend PTR-record worden aangemaakt zonder het correcte A-record eerst te verwijderen.

### 11. Gerichte DNS-provisioner en testscenario voorbereid

De DNS-provisioner kreeg een eigen naam:

```ruby
server1.vm.provision "dns-primary",
  type: "shell",
  path: "scripts/server1/configure-dns-server1.ps1"
```

Het gerichte testcommando:

```powershell
vagrant provision server1 --provision-with dns-primary
```

Er werd een gecontroleerd reset-scenario aangeleverd:

- Alleen de reverse zone verwijderen.
- Alleen de A-records van server2 en server3 verwijderen.
- Het A-record van server1 behouden.

Dit scenario test zowel het opnieuw aanmaken van records als het herstellen van een ontbrekend PTR-record wanneer het bijbehorende A-record al bestaat.

De forward AD-zone, `_msdcs`, DNS-rol en domeincontroller hoeven hiervoor niet verwijderd te worden.

De uitvoering van alle resetcommando's is niet afzonderlijk met output vastgelegd.

### 12. Provisioningfout na DNS-serviceherstart opgelost

Tijdens de test werd het algemene commando uitgevoerd:

```powershell
vagrant provision server1
```

De output toonde:

- Netwerkprovisioner uitgevoerd.
- Promotiescript detecteerde dat server1 al domeincontroller was.
- Vagrant voerde toch een reboot uit vanwege `reboot: true`.
- DNS-provisioner startte.
- Forward zone was aanvankelijk bereikbaar.
- Instellen van het DNS-luisteradres slaagde.
- Na de DNS-serviceherstart faalde `Get-DnsServerZone`.

Foutmelding:

```text
Get-DnsServerZone : Failed to enumerate zones from the server SERVER1.
FullyQualifiedErrorId : WIN32 21,Get-DnsServerZone
```

Waarschijnlijke oorzaak: de DNS-service had status Running, maar de AD-geïntegreerde zones waren nog niet gereed voor beheeropdrachten.

Het oorspronkelijke script wachtte alleen op de servicestatus. Dat werd vervangen door een readiness-check:

- `Get-DnsServerZone` herhaald proberen.
- Controleren of de AD-forward zone daadwerkelijk geladen is.
- Vijf seconden wachten tussen pogingen.
- Na maximaal 180 seconden stoppen met een duidelijke fout.

Event 4013 werd als mogelijke diagnostische aanwijzing besproken, maar niet met logoutput vastgesteld. De exacte oorzaak van WIN32 21 is daarom niet definitief bewezen.

### 13. Eindverificatie van DNS

Om 15:28 werden zones en records opnieuw gecontroleerd:

```powershell
Get-DnsServerZone |
    Select-Object ZoneName, ZoneType, IsDsIntegrated

Get-DnsServerResourceRecord -ZoneName "WS26-JD.hogent" -RRType A |
    Select-Object HostName,
        @{Name="IP"; Expression={$_.RecordData.IPv4Address}}

Get-DnsServerResourceRecord `
    -ZoneName "26.168.192.in-addr.arpa" -RRType PTR |
    Select-Object HostName,
        @{Name="Doel"; Expression={$_.RecordData.PtrDomainName}}
```

Resultaat zones:

| Zone | Type | AD-geïntegreerd |
|---|---|---|
| WS26-JD.hogent | Primary | True |
| 26.168.192.in-addr.arpa | Primary | True |
| _msdcs.WS26-JD.hogent | Primary | True |

Resultaat A-records in de domeinzone:

| HostName | IP |
|---|---|
| @ | 192.168.26.10 |
| DomainDnsZones | 192.168.26.10 |
| ForestDnsZones | 192.168.26.10 |
| server1 | 192.168.26.10 |
| server2 | 192.168.26.20 |
| server3 | 192.168.26.30 |

Resultaat PTR-records:

| HostName | Doel |
|---|---|
| 10 | server1.WS26-JD.hogent. |
| 20 | server2.WS26-JD.hogent. |
| 30 | server3.WS26-JD.hogent. |

De huidige zones en records staan correct. De definitieve succesvolle Vagrant-uitvoer na de readiness-aanpassing werd niet meegegeven; de eindcontrole bevestigt wel de gewenste toestand op de VM.

## Problemen tegengekomen en oplossingen

| Probleem | Oorzaak of vaststelling | Oplossing |
|---|---|---|
| Onduidelijkheid over de opdrachtversie | Eerdere PDF bevatte een draftmelding | Nieuwe aangeleverde PDF gecontroleerd; geen relevante wijzigingen vastgesteld voor Deel 1 |
| Twijfel over destroy/up versus provision | Nieuwe provisioner toegevoegd aan bestaande VM | Provisioning gebruiken; geen VM-herbouw nodig voor deze test |
| Onverwachte reboot bij algemene provisioning | Promotie-provisioner bevat `reboot: true`, ook bij overslaan van promotie | DNS-provisioner benoemen en gericht uitvoeren met `--provision-with dns-primary` |
| NAT-IP in DNS-records | Bestaande ongewenste records bleven aanwezig ondanks uitgeschakelde NAT-clientregistratie | NAT-A-records gericht verwijderen en DNS-luisterinterface beperken |
| PTR-record server1 ontbrak | Eerste script sloeg PTR-aanmaak over zodra A-record bestond | A- en PTR-records afzonderlijk controleren en herstellen |
| WIN32 21 bij zone-enumeratie na DNS-herstart | Waarschijnlijk DNS-zones nog niet gereed, ondanks servicestatus Running | Readiness-check toevoegen die wacht tot de AD-forward zone geladen is |
| Te ruime conclusies uit groepscontrole | Niet in Domain Admins zijn bewijst niet automatisch afwezigheid van alle adminrechten | Verificatie nauwkeurig beschrijven als controle van direct Domain Admins-lidmaatschap |

## Status einde sessie

**Afgerond:**

- [x] server1 gepromoveerd tot domeincontroller van WS26-JD.hogent
- [x] Domain functional level Windows Server 2025 bevestigd
- [x] Forest functional level Windows Server 2025 bevestigd
- [x] Vier eigen OU's aangemaakt en geverifieerd
- [x] Vier gebruikers aangemaakt en geplaatst in de juiste OU's
- [x] Twee nieuwe accounts bevestigd als directe leden van Domain Admins
- [x] Twee gewone accounts bevestigd als geen directe leden van Domain Admins
- [x] Opdrachtversies gecontroleerd op relevante wijzigingen
- [x] Primaire DNS-rol en forward/reverse zones aanwezig en geverifieerd
- [x] Alle drie servers hebben het juiste A-record en PTR-record
- [x] NAT-A-records uit de getoonde domeinzone verwijderd
- [x] DNS-script aangepast met afzonderlijke A-/PTR-controle en readiness-check
- [x] Benoemde DNS-provisioner opgenomen in de Vagrantfile

Nog te testen of af te werken:

- [ ] Tweede gerichte DNS-provisioning uitvoeren en vastleggen dat geen fouten of duplicaten ontstaan
- [ ] Reboot-test uitvoeren zonder daarna eerst te provisionen; controleren of NAT-records wegblijven
- [ ] DNS-registratiebeleid op server2, server3 en client verder configureren
- [ ] Secundaire DNS op server2 installeren en configureren
- [ ] NS-records, transferinstellingen en daadwerkelijke zone transfers verifiëren
- [ ] Deployment guide en status log aanvullen met de DNS-resultaten
- [ ] Overige diensten afwerken: DHCP, CA, IIS, RSAT en firewallconfiguratie

De AD-basis en huidige primaire DNS-configuratie zijn werkend geverifieerd. Herhaalbaarheid, behoud van correcte records na reboot en secundaire DNS blijven afzonderlijke testpunten.