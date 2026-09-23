# Windows Server II Portfolio - WS26-[JOUW_INITIALEN]

Portfolio voor het OLOD Windows Server II (HOGENT, 2026-2027).

## Structuur van deze repo

```
.
├── Vagrantfile              # Basis Vagrantfile (van Orion) + eigen aanpassingen
├── scripts/
│   ├── server1/             # DC + Primaire DNS + IIS
│   ├── server2/             # Secundaire DNS (+ later SQL node)
│   ├── server3/             # CA + DHCP (+ later SQL node)
│   └── client/              # Windows 11 + RSAT
├── docs/
│   ├── deployment-guide.md  # Stappenplan voor uitrol (later omzetten naar readme.pdf bij indienen)
│   └── status-log.md        # Bijhouden van status / problemen / oplossingen tijdens het project
└── .gitignore
```

## Onderdelen (Deel 1 - Automatisatie basisdiensten)

| VM | OS | Rollen |
|---|---|---|
| server1 | Windows Server 2025 Core | AD DS, Primaire DNS, IIS |
| server2 | Windows Server 2025 Core | Secundaire DNS |
| server3 | Windows Server 2025 Core | CA, DHCP |
| client | Windows 11 Enterprise | RSAT tools |

Netwerk: Host-Only 192.168.26.0/24 (server1=.10, server2=.20, server3=.30, client via DHCP van server3).

Domeinnaam: `WS26-[initialen].hogent`

## Belangrijke deadlines

- Deel 1 (Automatisatie): zondag 15/11/2026, 15:00
- Deel 2 (IIS + SQL failover): zondag 13/12/2026, 15:00

## Workflow

1. Werk per script/onderdeel in een eigen branch of commit klein en vaak.
2. Test elk script apart voordat je de volledige omgeving via `vagrant up` uitrolt.
3. Documenteer problemen en oplossingen meteen in `docs/status-log.md` - dit is nuttig voor de reflectie in de deployment guide.
4. Voeg **geen** ISO's, `.vagrant/`-map, boxbestanden of installers toe aan git (zie `.gitignore`).

## Indienen

Voor de uiteindelijke indiening (ZIP, max 5MB) exporteer je enkel de nodige bestanden:
`readme.pdf`, `demo.txt`, `scripts/` (zie opdrachtdocument voor exacte structuur).
