# Testdocument — Windows Server II Portofolio

> Dit document bevat de volledige acceptatietest voor alle tot nu toe geïmplementeerde onderdelen:  
> netwerk, Active Directory, gebruikers, DNS, Certification Authority en Web Enrollment.  
> Voer de testen uit in de aangegeven volgorde.

## 0. Voorbereiding

### 0.1 Omgeving starten

Voer vanuit de map met de `Vagrantfile` uit:

```powershell
vagrant status
```

Verwacht resultaat:

```text
server1  running (virtualbox)
server2  running (virtualbox)
server3  running (virtualbox)
```

Als één of meerdere VM’s niet draaien:

```powershell
vagrant up server1
vagrant up server2
vagrant up server3
```

### 0.2 Testmatrix

| Nr. | Onderdeel | Verwacht resultaat |
|---:|---|---|
| 1 | Netwerkconfiguratie | Elke server heeft het juiste statische Host-Only IP |
| 2 | Active Directory | server1 is DC van `WS26-JD.hogent` op Windows Server 2025-level |
| 3 | OU’s en gebruikers | Vier OU’s en vier gebruikers zijn aanwezig |
| 4 | DNS-primaire zones | server1 bevat de vereiste primaire zones en records |
| 5 | DNS-secundaire zones | server2 bevat de vereiste secundaire zones |
| 6 | DNS-zone transfer | Een wijziging op server1 wordt gerepliceerd naar server2 |
| 7 | Certification Authority | De Enterprise Root CA draait op server3 |
| 8 | Web Enrollment HTTPS | De HTTPS-pagina is bereikbaar met domeincredentials |
| 9 | Web Enrollment HTTP | HTTP verwijst automatisch door naar HTTPS |
| 10 | Geautomatiseerde verificatie | De Web Enrollment-provisioner slaagt vanaf server1 |

---

## 1. Netwerkconfiguratie

### 1.1 IP-adressen controleren

Voer op elke server uit:

```powershell
vagrant ssh server1
powershell
Get-NetIPConfiguration -InterfaceAlias "Ethernet 2"
exit
exit
```

Herhaal dit voor `server2` en `server3`.

Verwacht resultaat:

| Server | Host-Only IP-adres |
|---|---|
| server1 | `192.168.26.10/24` |
| server2 | `192.168.26.20/24` |
| server3 | `192.168.26.30/24` |

### 1.2 Netwerkconnectiviteit controleren

Voer op server1 uit:

```powershell
vagrant ssh server1
powershell

Test-NetConnection 192.168.26.20 -InformationLevel Detailed
Test-NetConnection 192.168.26.30 -InformationLevel Detailed
```

Verwacht resultaat:

```text
PingSucceeded : True
```

### 1.3 DNS-naamresolutie controleren

Voer op server1 uit:

```powershell
Resolve-DnsName server1.WS26-JD.hogent
Resolve-DnsName server2.WS26-JD.hogent
Resolve-DnsName server3.WS26-JD.hogent
```

Verwacht resultaat:

| Naam | IP-adres |
|---|---|
| `server1.WS26-JD.hogent` | `192.168.26.10` |
| `server2.WS26-JD.hogent` | `192.168.26.20` |
| `server3.WS26-JD.hogent` | `192.168.26.30` |

### 1.4 VirtualBox DHCP-control

Voer op de Windows-host uit:

```powershell
VBoxManage list dhcpservers
```

Verwacht resultaat: geen actieve DHCP-server op het Host-Only netwerk `192.168.26.0/24`.

---

## 2. Active Directory

### 2.1 Domeincontroller controleren

Voer op server1 uit:

```powershell
vagrant ssh server1
powershell

Get-ADDomain | Select-Object Name, DomainMode
Get-ADForest | Select-Object Name, ForestMode
```

Verwacht resultaat:

```text
Name       DomainMode
----       ----------
WS26-JD    Windows2025Domain


Name       ForestMode
----       ----------
WS26-JD    Windows2025Forest
```

### 2.2 Domeincontrollerrollen controleren

Voer op server1 uit:

```powershell
Get-ADDomainController |
    Select-Object Name, Domain, Forest, Site, IPv4Address
```

Verwacht resultaat:

```text
Name    Domain          Forest          IPv4Address
----    ------          ------          -----------
SERVER1 WS26-JD.hogent  WS26-JD.hogent  192.168.26.10
```

### 2.3 AD-diensten controleren

Voer op server1 uit:

```powershell
Get-Service NTDS, DNS, Netlogon |
    Select-Object Name, DisplayName, Status
```

Verwacht resultaat:

| Service | Status |
|---|---|
| `NTDS` | `Running` |
| `DNS` | `Running` |
| `Netlogon` | `Running` |

---

## 3. OU’s en gebruikers

### 3.1 OU-structuur controleren

Voer op server1 uit:

```powershell
Get-ADOrganizationalUnit -Filter * |
    Select-Object Name, DistinguishedName |
    Sort-Object Name
```

Verwacht resultaat: minstens deze OU’s zijn aanwezig:

```text
Beheer
Medewerkers
Servers
Clients
```

### 3.2 Gebruikers controleren

Voer op server1 uit:

```powershell
Get-ADUser -Filter * |
    Select-Object Name, SamAccountName, Enabled |
    Sort-Object SamAccountName
```

Verwacht resultaat: minstens deze gebruikers zijn aanwezig en ingeschakeld:

| Weergavenaam | Account |
|---|---|
| John Doe | `j.doe.adm` |
| Anna Smit | `a.smit.adm` |
| Piet Jansen | `p.jansen` |
| Marie Peeters | `m.peeters` |

### 3.3 Domeinadmins controleren

Voer op server1 uit:

```powershell
Get-ADGroupMember -Identity "Domain Admins" |
    Select-Object Name, SamAccountName
```

Verwacht resultaat: minstens deze accounts zijn lid:

```text
Administrator
j.doe.adm
a.smit.adm
```

### 3.4 Domeingebruikers controleren

Voer op server1 uit:

```powershell
Get-ADGroupMember -Identity "Domain Users" |
    Select-Object Name, SamAccountName
```

Verwacht resultaat: `p.jansen` en `m.peeters` zijn aanwezig.

Controleer ook dat zij geen Domain Admin zijn:

```powershell
Get-ADGroupMember -Identity "Domain Admins" |
    Where-Object SamAccountName -in @("p.jansen", "m.peeters")
```

Verwacht resultaat: geen output.

---

## 4. DNS op server1

### 4.1 DNS-zones controleren

Voer op server1 uit:

```powershell
Get-DnsServerZone |
    Select-Object ZoneName, ZoneType, IsSigned |
    Sort-Object ZoneName
```

Verwacht resultaat: minstens deze zones zijn aanwezig als `Primary`:

```text
WS26-JD.hogent
_msdcs.WS26-JD.hogent
```

Controleer ook de reverse zone:

```powershell
Get-DnsServerZone |
    Where-Object ZoneName -like "*26.168.192.in-addr.arpa" |
    Select-Object ZoneName, ZoneType
```

Verwacht resultaat:

```text
ZoneName                         ZoneType
--------                         --------
26.168.192.in-addr.arpa          Primary
```

### 4.2 A-records controleren

Voer op server1 uit:

```powershell
Get-DnsServerResourceRecord `
    -ZoneName "WS26-JD.hogent" `
    -RRType A |
    Select-Object HostName, RecordType, RecordData |
    Sort-Object HostName
```

Verwacht resultaat:

| Hostnaam | Type | IP-adres |
|---|---|---|
| `server1` | `A` | `192.168.26.10` |
| `server2` | `A` | `192.168.26.20` |
| `server3` | `A` | `192.168.26.30` |

### 4.3 PTR-records controleren

Voer op server1 uit:

```powershell
Get-DnsServerResourceRecord `
    -ZoneName "26.168.192.in-addr.arpa" `
    -RRType PTR |
    Select-Object HostName, RecordType, RecordData |
    Sort-Object HostName
```

Verwacht resultaat:

| Hostnaam | Type | Verwijst naar |
|---|---|---|
| `10` | `PTR` | `server1.WS26-JD.hogent` |
| `20` | `PTR` | `server2.WS26-JD.hogent` |
| `30` | `PTR` | `server3.WS26-JD.hogent` |

### 4.4 Geen NAT-adressen in DNS

Voer op server1 uit:

```powershell
Get-DnsServerResourceRecord `
    -ZoneName "WS26-JD.hogent" `
    -RRType A |
    Where-Object {
        $_.RecordData.IPv4Address.IPAddressToString -like "10.0.*"
    }
```

Verwacht resultaat: geen output.

---

## 5. DNS op server2

### 5.1 Secundaire zones controleren

Voer op server2 uit:

```powershell
vagrant ssh server2
powershell

Get-DnsServerZone |
    Where-Object ZoneType -eq "Secondary" |
    Select-Object ZoneName, ZoneType, MasterServers |
    Sort-Object ZoneName
```

Verwacht resultaat: minstens deze zones zijn `Secondary`:

```text
WS26-JD.hogent
_msdcs.WS26-JD.hogent
26.168.192.in-addr.arpa
```

### 5.2 Master-server controleren

Voer op server2 uit:

```powershell
Get-DnsServerZone |
    Where-Object ZoneType -eq "Secondary" |
    Select-Object ZoneName, MasterServers
```

Verwacht resultaat: elke secundaire zone verwijst naar `192.168.26.10`.

### 5.3 DNS-query via server2 controleren

Voer op server2 uit:

```powershell
Resolve-DnsName server3.WS26-JD.hogent `
    -Server 192.168.26.20
```

Verwacht resultaat:

```text
Name                : server3.WS26-JD.hogent
IPAddress           : 192.168.26.30
```

---

## 6. DNS-zone transfer

### 6.1 Testrecord aanmaken op server1

Voer op server1 uit:

```powershell
Add-DnsServerResourceRecordCName `
    -ZoneName "WS26-JD.hogent" `
    -Name "dns-transfer-test" `
    -HostNameAlias "server1.WS26-JD.hogent"
```

### 6.2 Replicatie naar server2 controleren

Voer op server2 uit:

```powershell
Resolve-DnsName dns-transfer-test.WS26-JD.hogent `
    -Server 192.168.26.20
```

Verwacht resultaat:

```text
Name                   : dns-transfer-test.WS26-JD.hogent
NameHost               : server1.WS26-JD.hogent
```

### 6.3 Testrecord verwijderen

Voer op server1 uit:

```powershell
Remove-DnsServerResourceRecord `
    -ZoneName "WS26-JD.hogent" `
    -RRType CNAME `
    -Name "dns-transfer-test"
```

Controleer daarna op server2 dat het record verdwenen is:

```powershell
Resolve-DnsName dns-transfer-test.WS26-JD.hogent `
    -Server 192.168.26.20
```

Verwacht resultaat: een DNS-fout of “record not found”.

---

## 7. Certification Authority op server3

### 7.1 CA-rol controleren

Voer op server3 uit:

```powershell
vagrant ssh server3
powershell

Get-WindowsFeature -Name AD-Certificate, AD-Cert-Authority, AD-Cert-Web-Enrollment |
    Select-Object Name, DisplayName, InstallState
```

Verwacht resultaat:

| Feature | InstallState |
|---|---|
| `AD-Certificate` | `Installed` |
| `AD-Cert-Authority` | `Installed` |
| `AD-Cert-Web-Enrollment` | `Installed` |

### 7.2 CA-service controleren

Voer op server3 uit:

```powershell
Get-Service CertSvc |
    Select-Object Name, DisplayName, Status
```

Verwacht resultaat:

```text
Name    DisplayName                              Status
----    -----------                              ------
CertSvc Active Directory Certificate Services    Running
```

### 7.3 CA-configuratie controleren

Voer op server3 uit:

```powershell
certutil -getconfig
```

Verwacht resultaat: de configuratie verwijst naar:

```text
WS26-JD-Root-CA
```

### 7.4 Rootcertificaat controleren

Voer op server3 uit:

```powershell
certutil -ca.cert C:\LabCertificates\WS26-JD-Root-CA.cer
certutil -dump C:\LabCertificates\WS26-JD-Root-CA.cer
```

Verwacht resultaat:

```text
Subject    : CN=WS26-JD-Root-CA, DC=WS26-JD, DC=hogent
Issuer     : CN=WS26-JD-Root-CA, DC=WS26-JD, DC=hogent
```

Controleer ook dat het bestand bestaat:

```powershell
Test-Path C:\LabCertificates\WS26-JD-Root-CA.cer
```

Verwacht resultaat:

```text
True
```

### 7.5 CA-certificaten controleren

Voer op server3 uit:

```powershell
Get-ChildItem Cert:\LocalMachine\CA |
    Where-Object Subject -like "*WS26-JD-Root-CA*" |
    Select-Object Subject, Issuer, Thumbprint, NotAfter
```

Verwacht resultaat: minstens één certificaat met subject `CN=WS26-JD-Root-CA`.

---

## 8. Web Enrollment via HTTPS

### 8.1 IIS en CertSrv controleren

Voer op server3 uit:

```powershell
Import-Module WebAdministration

Get-Website |
    Select-Object Name, State, PhysicalPath

Get-WebApplication |
    Where-Object Path -eq "/CertSrv" |
    Select-Object Path, ApplicationPool, PhysicalPath
```

Verwacht resultaat:

```text
Path        : /CertSrv
Application : DefaultAppPool
PhysicalPath: C:\WINDOWS\system32\CertSrv\en-US
```

### 8.2 HTTPS-certificaat controleren

Voer op server3 uit:

```powershell
Get-ChildItem Cert:\LocalMachine\My |
    Where-Object Subject -eq "CN=server3.WS26-JD.hogent" |
    Select-Object Subject, Issuer, Thumbprint, HasPrivateKey, NotAfter
```

Verwacht resultaat:

```text
Subject       : CN=server3.WS26-JD.hogent
Issuer        : CN=WS26-JD-Root-CA, DC=WS26-JD, DC=hogent
HasPrivateKey : True
```

### 8.3 HTTPS-binding controleren

Voer op server3 uit:

```powershell
Get-WebBinding |
    Where-Object protocol -eq "https" |
    Select-Object protocol, bindingInformation, certificateHash
```

Verwacht resultaat:

```text
protocol           : https
bindingInformation : *:443:
certificateHash    : <thumbprint van het server3-certificaat>
```

### 8.4 HTTPS-pagina testen vanaf server1

Voer op server1 uit:

```powershell
$SecurePassword = ConvertTo-SecureString `
    "<ADMINISTRATOR_WACHTWOORD>" `
    -AsPlainText `
    -Force

$Credential = [System.Management.Automation.PSCredential]::new(
    "WS26-JD\Administrator",
    $SecurePassword
)

$Page = Invoke-WebRequest `
    -Uri "https://server3.WS26-JD.hogent/certsrv/Default.asp" `
    -Credential $Credential `
    -UseBasicParsing `
    -TimeoutSec 30

$Page.StatusCode
([regex]::Match($Page.Content, '(?is)<title[^>]*>(.*?)</title>').Groups[1].Value)
```

Verwacht resultaat:

```text
200
Microsoft Active Directory Certificate Services
```

---

## 9. Web Enrollment via HTTP

### 9.1 HTTP-redirectbinding controleren

Voer op server3 uit:

```powershell
Get-WebBinding |
    Where-Object protocol -eq "http" |
    Select-Object protocol, bindingInformation
```

Verwacht resultaat:

```text
protocol           : http
bindingInformation : 192.168.26.30:80:server3.WS26-JD.hogent
```

### 9.2 HTTP-redirect testen vanaf server1

Voer op server1 uit:

```powershell
$HttpUrl = "http://server3.WS26-JD.hogent/CertSrv/"
$ExpectedDestination =
    "https://server3.WS26-JD.hogent/certsrv/Default.asp"

$Request = [System.Net.HttpWebRequest]::Create($HttpUrl)
$Request.AllowAutoRedirect = $false
$Request.Timeout = 30000

$Response = $Request.GetResponse()

try {
    [int]$Response.StatusCode
    $Response.Headers["Location"]
}
finally {
    $Response.Close()
}
```

Verwacht resultaat:

```text
302
https://server3.WS26-JD.hogent/certsrv/Default.asp
```

### 9.3 Volledige HTTP-naar-HTTPS-keten testen

Voer op server1 uit:

```powershell
$SecurePassword = ConvertTo-SecureString `
    "<ADMINISTRATOR_WACHTWOORD>" `
    -AsPlainText `
    -Force

$Credential = [System.Management.Automation.PSCredential]::new(
    "WS26-JD\Administrator",
    $SecurePassword
)

$Page = Invoke-WebRequest `
    -Uri "https://server3.WS26-JD.hogent/certsrv/Default.asp" `
    -Credential $Credential `
    -UseBasicParsing `
    -TimeoutSec 30

$Page.StatusCode
```

Verwacht resultaat:

```text
200
```

---

## 10. Geautomatiseerde Web Enrollment-verificatie

### 10.1 Provisioner uitvoeren

Voer op de Windows-host uit:

```powershell
vagrant provision server1 --provision-with server1-verify-web-enrollment
```

### 10.2 Verwacht resultaat

```text
server1: Controle Web Enrollment vanaf server1...
server1: HTTP-ingang: http://server3.WS26-JD.hogent/CertSrv/
server1: HTTP-redirect: 302 naar https://server3.WS26-JD.hogent/certsrv/Default.asp
server1: HTTPS-pagina: HTTP 200
server1: Paginatitel: Microsoft Active Directory Certificate Services
server1: Web Enrollment is correct bereikbaar via http://server3.WS26-JD.hogent/CertSrv/.
```

### 10.3 Acceptatiecriterium

Het onderdeel is geslaagd als:

- de HTTP-URL een `302` retourneert;
- de redirect-bestemming exact gelijk is aan de HTTPS-startpagina;
- de HTTPS-pagina met domeincredentials HTTP `200` retourneert;
- de paginatitel `Microsoft Active Directory Certificate Services` bevat.

---

## 11. Firewallcontrole

### 11.1 DNS-firewallregels controleren

Voer op server1 en server2 uit:

```powershell
Get-NetFirewallRule |
    Where-Object DisplayName -like "*DNS*" |
    Select-Object DisplayName, Enabled, Direction, Action
```

Verwacht resultaat: de relevante DNS-regels zijn `Enabled` en staan op `Allow`.

### 11.2 Web Enrollment-firewallregels controleren

Voer op server3 uit:

```powershell
Get-NetFirewallRule |
    Where-Object {
        $_.DisplayName -like "*HTTPS*" -or
        $_.DisplayName -like "*HTTP*"
    } |
    Select-Object DisplayName, Enabled, Direction, Action
```

Verwacht resultaat: de interne regels voor HTTP en HTTPS zijn actief.

### 11.3 Poortcontrole vanaf server1

Voer op server1 uit:

```powershell
Test-NetConnection server3.WS26-JD.hogent -Port 80
Test-NetConnection server3.WS26-JD.hogent -Port 443
```

Verwacht resultaat:

```text
TcpTestSucceeded : True
```

---

## 12. Eindresultaat

| Onderdeel | Status |
|---|---|
| Netwerkconfiguratie | Geslaagd |
| Active Directory | Geslaagd |
| OU’s en gebruikers | Geslaagd |
| DNS-primaire configuratie | Geslaagd |
| DNS-secundaire configuratie | Geslaagd |
| DNS-zone transfer | Geslaagd |
| Certification Authority | Geslaagd |
| Web Enrollment via HTTPS | Geslaagd |
| Web Enrollment via HTTP | Geslaagd |
| Geautomatiseerde Web Enrollment-verificatie | Geslaagd |

### Bekende openstaande punten

- DHCP-rol en DHCP-scope op server3 zijn nog niet geïnstalleerd.
- GPO voor automatisch vertrouwen van de CA is nog niet geconfigureerd.
- IIS “Hello World”-pagina op server1 ontbreekt nog.
- RSAT op de Windows 11-client ontbreekt nog.
- Het CA-script vraagt bij herhaalde provisioning nog steeds een nieuw websitecertificaat aan; certificaathergebruik moet nog worden toegevoegd.
