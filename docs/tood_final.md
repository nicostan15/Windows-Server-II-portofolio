Vervang je huidige week 6 door onderstaande uitgebreide checklist. De punten over server2, netwerkvoorbereiding, oude wrappers en foutafhandeling komen uit de controle van je projectexport. [1489]

## Week 6 — 02/11 t/m 08/11: Automatiseren, configuratie opruimen & volledige uitrol testen

### 1. Werkende versie veiligstellen

- [ ] Huidige werkende scripts en `Vagrantfile` vastleggen in Git vóór verdere wijzigingen.
- [ ] Herstelmogelijkheid voorzien voor de werkende omgeving vóór de schone opbouwtest.
- [ ] Succesvolle testuitvoer bewaren in het testdocument: CA-vertrouwen, Web Enrollment en intranet.
- [ ] Wijzigingen per onderdeel uitvoeren en testen, niet alles tegelijk aanpassen.

### 2. Netwerkconfiguratie en domeinjoins afwerken

- [ ] Server2: interne DNS-server `192.168.26.10` instellen vóór de domeinjoin.
- [ ] Server2: domeinjoin uitvoeren via `server2-domain` en herstart laten afhandelen door Vagrant.
- [ ] Controleren dat alle drie de servers en de client lid zijn van `WS26-JD.hogent`.
- [ ] Client: expliciete netwerkvoorbereiding toevoegen of aantonen dat de standaardinstellingen bij een nieuwe uitrol volstaan:
  - [ ] Host-Only-interface gebruikt DHCP.
  - [ ] Client ontvangt een adres van Windows DHCP op server3.
  - [ ] Client ontvangt beide interne DNS-servers en het juiste DNS-suffix.
  - [ ] Netwerk en domein-DNS zijn beschikbaar vóór de domeinjoin.
- [ ] `configure-network.ps1` verbeteren: precies één geschikte interne interface selecteren en bestaande configuratie controleren.
- [ ] Waar mogelijk interfaces herkennen aan hun functie/IP-configuratie in plaats van uitsluitend aan de naam `Ethernet 2`.
- [ ] Controleren dat NAT-interfaces en de client zichzelf niet registreren in DNS.
- [ ] VirtualBox Host-Only-DHCP controleren: uitgeschakeld, zodat alleen Windows DHCP de client bedient.

### 3. Vagrantfile en uitvoeringsvolgorde controleren

- [ ] Provisioningvolgorde per machine nalopen:
  - [ ] Netwerk en DNS vóór domeinjoin.
  - [ ] Domeinjoin en herstart vóór domeinafhankelijke configuratie.
  - [ ] CA beschikbaar vóór CA-afhankelijke configuratie op andere machines.
  - [ ] Templatepermissies beschikbaar vóór de certificaataanvraag die ze nodig heeft.
  - [ ] CA-vertrouwen aanwezig vóór HTTPS-verificatie.
- [ ] Afhankelijkheden tussen `server1`, `server2`, `server3` en `client` controleren.
- [ ] Controleren of `run: "always"`, `run: "never"` en standaardprovisioning bewust en correct gebruikt worden.
- [ ] Controleren dat herstarts niet dubbel worden gestart door zowel PowerShell als Vagrant.
- [ ] De `after :up`-trigger op server3 controleren en documenteren wanneer die wel/niet wordt uitgevoerd.
- [ ] Controleren of losse herprovisioning dezelfde noodzakelijke afhankelijkheden afhandelt, of de vereiste volgorde documenteren.
- [ ] Domeinnaam, CA-naam en labcredentials consequent vanuit configuratie doorgeven waar mogelijk.
- [ ] Boxnamen en vastgepinde versies ongewijzigd laten.
- [ ] Verouderde opmerkingen bijwerken, zoals “firewall alleen expliciet uitvoeren” terwijl `run: "always"` ingesteld staat.

### 4. CA, GPO en certificaatlogica controleren

- [ ] Uitgebreide CA- en Web Enrollment-configuratie inhoudelijk nalopen.
- [ ] Volgorde van templatepublicatie, templatepermissies en certificaataanvraag controleren.
- [ ] Controleren dat certificaatcontroles geen oude, vastgepinde thumbprint gebruiken.
- [ ] Huidig Root-CA-certificaat vergelijken met het certificaat in Trusted Root.
- [ ] Root-CA-vertrouwen controleren op alle vier de machines.
- [ ] Controleren dat de GPO aan het juiste domein/OU-bereik gekoppeld is.
- [ ] Controleren dat herhaalde uitvoering geen onbedoelde extra instellingen of rechten toevoegt.
- [ ] Tijdelijke taken en werkbestanden controleren op resultaatcontrole en opruiming bij succes én fouten.

### 5. Scripts en mappenstructuur opruimen

- [ ] Consistente bestandsnamen en een duidelijke nummering/indeling kiezen.
- [ ] Bij iedere hernoeming alle verwijzingen in de Vagrantfile en documentatie aanpassen.
- [ ] Ongebruikte placeholders na controle op verwijzingen uit de definitieve scripts verwijderen:
  - [ ] `scripts/client/01-join-domain.ps1`
  - [ ] `scripts/server2/01-network.ps1`
  - [ ] `scripts/server2/04-firewall.ps1`
  - [ ] `scripts/server3/01-network.ps1`
  - [ ] `scripts/server3/05-firewall.ps1`
- [ ] Oude firewallwrappers verwijderen of corrigeren; deze gebruiken nog de oude parameters `-AllowedPorts` en `-RoleName`:
  - [ ] `scripts/client/03-firewall.ps1`
  - [ ] `scripts/server1/10-firewall.ps1`
  - [ ] `scripts/server2/10-firewall.ps1`
- [ ] Overbodige, dubbele en verouderde code verwijderen.
- [ ] Onjuiste comments en achtergebleven `TODO`-meldingen opruimen.
- [ ] Inspringing en opmaak consistent maken.
- [ ] Tekstcodering controleren en fout weergegeven tekens herstellen.
- [ ] Gebruikers, OU’s en relevante labinstellingen eenvoudig aanpasbaar houden.
- [ ] Geen echte persoonlijke wachtwoorden, tokens of privésleutels in de definitieve projectbestanden opnemen.

### 6. Foutafhandeling en herbruikbaarheid verbeteren

- [ ] `$ErrorActionPreference = "Stop"` consequent toepassen waar scripts bij fouten moeten stoppen.
- [ ] Exitcodes controleren van externe programma’s zoals `certutil`, `gpupdate`, `netsh` en `dnscmd`.
- [ ] Resultaten controleren van rol- en feature-installaties.
- [ ] Voorcontroles toevoegen voor machine, domein, netwerkinterface en vereiste rollen.
- [ ] Bestaande afwijkende configuratie duidelijk melden in plaats van stilzwijgend overschrijven.
- [ ] Wachten op daadwerkelijke beschikbaarheid van diensten, met begrensde wachttijden en duidelijke foutmeldingen.
- [ ] Controleren dat herhaalde uitvoering geen dubbele objecten of ongewenste wijzigingen veroorzaakt.
- [ ] Problemen met shared folders na domeinjoin/promotie afhandelen; benodigde scripts lokaal beschikbaar maken.
- [ ] Voortgangsmeldingen toevoegen zodat zichtbaar is bij welke stap een script wacht of faalt.

### 7. Firewallconfiguratie definitief controleren

- [ ] Actieve firewallregels en hun poort-, service-, interface- en adresfilters per server nalopen.
- [ ] Controleren of de brede dynamische RPC-regel op server3 noodzakelijk is of gerichter kan.
- [ ] Controleren dat DNS-, IIS- en CA-scripts en het centrale firewallscript geen tegenstrijdige regels beheren.
- [ ] Firewall ingeschakeld houden met de bedoelde standaardpolicy.
- [ ] Na eventuele aanscherping opnieuw testen: domeinjoin, DNS, DHCP, CA, Web Enrollment en IIS.
- [ ] `vagrant ssh` en Vagrant-beheer blijven werken zonder de firewall uit te schakelen.

### 8. Functionele eindcontrole

- [ ] AD: domein- en forestfunctionaliteitsniveau controleren.
- [ ] AD: minstens drie OU’s en de vereiste gebruikers/rechten controleren.
- [ ] DNS: forward- en reversezones, A-/PTR-records en naamservers controleren.
- [ ] DNS: zoneoverdracht aantonen met een tijdelijk record op de primaire DNS-server.
- [ ] DHCP: scope, exclusion, opties, autorisatie en interfacebinding controleren.
- [ ] Client: DHCP-lease en ontvangen DNS-instellingen controleren.
- [ ] CA: automatisch vertrouwen op alle domeintoestellen controleren.
- [ ] Web Enrollment via de vereiste HTTP-ingang en de ingestelde HTTPS-bestemming testen.
- [ ] IIS: `Hello World` via `http://intranet.WS26-JD.hogent` vanaf de client controleren.
- [ ] RSAT: geselecteerde tools en het benodigde remote beheer voor de demo testen.
- [ ] Testresultaten en eventuele resterende beperkingen vastleggen.

### 9. Schone uitrol en herhaalbaarheid testen

- [ ] Na veiligstellen van de werkende omgeving een volledige uitrol vanaf nul uitvoeren.
- [ ] Vastleggen welke commando’s nodig zijn en welke stappen automatisch verlopen.
- [ ] Controleren dat geen herstelcommando’s of niet-gedocumenteerde handmatige configuratie nodig zijn.
- [ ] Eventuele fouten in de scripts herstellen en de betrokken stappen opnieuw testen.
- [ ] Na de schone uitrol ook stoppen en opnieuw starten testen.
- [ ] Gerichte herprovisioning testen zonder bestaande configuratie onbedoeld te beschadigen.
- [ ] Noodzakelijke handmatige stappen opnemen in de deployment guide als volledige automatisering niet lukt.

### 10. Afronden voor documentatie en video

- [ ] Definitieve werkende versie vastleggen in Git.
- [ ] Alleen benodigde scripts, configuratiebestanden en de Vagrantfile klaarzetten voor indiening.
- [ ] Testdocument actualiseren met wat bewezen werkt en wat nog beperkt is.
- [ ] Uitrolvolgorde, gebruikers en labwachtwoorden klaarzetten voor de deployment guide.
- [ ] Doel: scripts en omgeving werkend én getest tegen zondag **08/11**, zodat de laatste week beschikbaar blijft voor documentatie en demo-video.