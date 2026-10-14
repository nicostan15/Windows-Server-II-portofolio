# Follow-up — Windows Server II, Deel 1

**Datum:** woensdag 30/09/2026
**Sessie:** 10:05 – 12:30 CEST
**Onderwerp:** Host-Only IP-configuratie van server1, server2, server3 + VirtualBox DHCP-check (Week 2 van planning)

---

## Uitgangspunt

Taak uit de planning:

- [x] Host-Only IP-configuratie via PowerShell instellen (niet via Vagrant)
  - server1: 192.168.26.10, server2: 192.168.26.20, server3: 192.168.26.30
- [x] VirtualBox interne DHCP-server uitschakelen (client moet IP via Windows DHCP krijgen)

Bij aanvang van de sessie waren alle 4 VMs (server1, server2, server3, client) al succesvol uitgerold met `vagrant up` (adapters correct: adapter 1 = nat, adapter 2 = hostonly). Project staat lokaal in een **OneDrive-gesynchroniseerde map** — dit werkte vandaag probleemloos, maar blijft een aandachtspunt voor later (mogelijke sync-conflicten of trage I/O).

## Wat is er vandaag gedaan

### 1. Interface identificatie
Op server1 was er twijfel over cmd vs. PowerShell: `Get-NetAdapter` gaf eerst een foutmelding ("not recognized") omdat er in **cmd.exe** gewerkt werd in plaats van PowerShell. Opgelost door `powershell` te typen om over te schakelen.

Met `Get-NetAdapter` + `Get-NetIPConfiguration` werd de juiste interface geïdentificeerd:
- **Ethernet** (NAT) → IP 10.0.2.15, gateway 10.0.2.2 → niet aanraken
- **Ethernet 2** (Host-Only) → link-local 169.254.x.x, geen gateway → deze configureren

### 2. Manueel IP instellen
Met `New-NetIPAddress -InterfaceAlias "Ethernet 2" -IPAddress <ip> -PrefixLength 24` werden de drie servers correct geconfigureerd:

| Server | IP | Resultaat |
|---|---|---|
| server1 | 192.168.26.10 | Geslaagd |
| server2 | 192.168.26.20 | Geslaagd (eerste poging afgekapt door onvolledige paste — `-IPAddres` zonder rest — tweede poging lukte) |
| server3 | 192.168.26.30 | Geslaagd |

De `AddressState: Tentative`/`Invalid` in de output is normaal gedrag (duplicate address detection) en geen probleem.

### 3. Connectiviteit testen — Firewall-issue
Eerste `Test-NetConnection` vanaf server1 naar server2/server3 gaf **TimedOut**. Diagnose: Windows Defender Firewall staat standaard aan op alle profielen (Domain/Private/Public = `True`), en blokkeert ICMP.

Tijdelijk (enkel ter test, niet voor definitieve scripts) uitgeschakeld met:
```powershell
Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled False
```
Na uitschakelen: beide pings geslaagd (RTT 1 ms). Bevestigt dat de netwerkconfiguratie zelf correct was en de firewall de enige blokkerende factor was.

**Openstaand actiepunt:** firewall terug inschakelen op server2/server3, en in Week 5 gerichte inkomende regels voorzien (ICMP, DNS, DHCP, AD-poorten, WinRM/RDP) in plaats van de firewall uit te laten staan.

### 4. Script gemaakt: `configure-network.ps1`
Manuele configuratie omgezet naar een herbruikbaar, idempotent script met parameter `-IPAddress`:

```powershell
param(
    [Parameter(Mandatory=$true)]
    [string]$IPAddress
)

$adapter = Get-NetAdapter | Where-Object {
    (Get-NetIPConfiguration -InterfaceIndex $_.ifIndex).IPv4DefaultGateway -eq $null
}

if (-not (Get-NetIPAddress -InterfaceAlias $adapter.Name -IPAddress $IPAddress -ErrorAction SilentlyContinue)) {
    New-NetIPAddress -InterfaceAlias $adapter.Name -IPAddress $IPAddress -PrefixLength 24
}
```

Script opgeslagen in `scripts/configure-network.ps1`, bereikbaar op elke VM via de gedeelde map `C:\vagrant\scripts`.

**Testresultaten:**
- Server1: getest met IP al aanwezig (skip-pad) én na `Remove-NetIPAddress` (nieuw instellen-pad) — beide paden werkten correct.
- Server2 en server3: uitgevoerd zonder fouten, IP correct ingesteld.
- Kleine bijwerking opgemerkt: na de remove/re-add test op server1 bleef een extra link-local adres (169.254.146.77) op de interface staan naast het echte IP — onschadelijk, ontstaan puur door het test-scenario, geen impact op een normale `vagrant up`/`reload`.

### 5. Automatisatie via Vagrantfile
Provisioning-regels toegevoegd aan de bestaande Vagrantfile (per server, binnen het `config.vm.define`-blok):

```ruby
server1.vm.provision "shell", path: "scripts/configure-network.ps1", args: "-IPAddress 192.168.26.10"
```
(analoog voor server2 → .20 en server3 → .30; client blijft ongewijzigd, krijgt IP later via DHCP)

Aangepaste, volledige Vagrantfile werd aangeleverd, en getest met `vagrant reload --provision`. In de Vagrant-output verscheen bij server1, server2 en server3 telkens `Running provisioner: shell... Running: scripts/configure-network.ps1`, zonder foutmeldingen.

**Verificatie na reload** (via `Get-NetIPConfiguration -InterfaceAlias "Ethernet 2"` op elke server):

| Server | IP na automatische reload |
|---|---|
| server1 | 192.168.26.10 ✅ |
| server2 | 192.168.26.20 ✅ |
| server3 | 192.168.26.30 ✅ |

De volledige Host-Only IP-configuratie verloopt nu dus zonder enige manuele tussenkomst bij `vagrant up`/`vagrant reload`.

### 6. VirtualBox interne DHCP-server controleren/uitschakelen
Gecontroleerd met `VBoxManage list dhcpservers`. Resultaat: twee DHCP-servers geregistreerd op het systeem.

| NetworkName | Netwerk | Enabled | Relevant voor deze opdracht? |
|---|---|---|---|
| HackingLab | 10.0.2.0/24 (NAT, van een ander/vorig project) | Yes | Nee — niet aanraken |
| HostInterfaceNetworking-VirtualBox Host-Only Ethernet Adapter #2 | 192.168.26.0/24 (Host-Only van deze opdracht) | **No** | Ja — dit is het relevante netwerk |

De DHCP-server op het relevante Host-Only netwerk stond **al uitgeschakeld** vóór enige actie — vermoedelijk automatisch doordat de Vagrantfile `auto_config: false` gebruikt voor de private_network-adapters. De uitgevoerde `VBoxManage dhcpserver modify --ifname "VirtualBox Host-Only Ethernet Adapter #2" --disable`-commando's bevestigden enkel de reeds bestaande toestand (geen wijziging, geen fout bij herhaling). Taak is hiermee afgerond zonder verdere actie nodig.

## Problemen tegengekomen (en oplossingen)

| Probleem | Oorzaak | Oplossing |
|---|---|---|
| `Get-NetAdapter` niet herkend | Gebruiker zat in cmd.exe, niet PowerShell | Typ `powershell` om te schakelen |
| `New-NetIPAddress` argument-fout | Commando afgekapt bij copy-paste | Volledige regel in één keer plakken |
| Ping tussen servers faalt (TimedOut) | Windows Defender Firewall blokkeert ICMP standaard | Tijdelijk uitschakelen ter test; structurele oplossing (gerichte regels) gepland in Week 5 |
| Extra link-local IP na test | Bijwerking van manuele Remove/Re-add test | Onschadelijk, treedt niet op bij normale vagrant-uitrol |
| `VBoxManage dhcpserver modify --network=<placeholder>` gaf "DHCP server does not exist" | Placeholdertekst niet vervangen door echte netwerknaam/ifname | Correct commando met `--ifname "VirtualBox Host-Only Ethernet Adapter #2"` gebruikt |

## Status einde sessie

Host-Only IP-configuratie is **volledig afgerond, manueel én automatisch geverifieerd** op alle 3 servers (via `vagrant reload --provision`). VirtualBox interne DHCP-server op het relevante Host-Only netwerk is bevestigd uitgeschakeld. Beide items uit Week 2 van de planning kunnen worden afgevinkt.