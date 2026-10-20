# Windows Server II - Vagrant template
# 2026-2027
# ------------------------------------
#
# Omgeving:
# - 3 Windows Server 2025 Core-machines
# - 1 Windows 11 Enterprise-client
#
# De boxnamen en vastgepinde versies mogen niet gewijzigd worden.
#
# Elke VM heeft twee netwerkinterfaces:
# - NAT: internet en Vagrant
# - Host-Only: interne communicatie
#
# De IP-adressen in private_network zijn placeholders.
# De echte Host-Only IP-configuratie gebeurt via PowerShell.
#
# Alle VM's starten:
#   vagrant up
#
# Alleen primaire DNS opnieuw configureren:
#   vagrant provision server1 --provision-with dns-primary
#
# Alleen secundaire DNS opnieuw configureren:
#   vagrant provision server2 --provision-with dns-secondary

Vagrant.configure("2") do |config|

  # ------------------------------------------------------------------
  # WinRM-workaround voor de huidige labomgeving na AD-promotie.
  # Bestaande werkende instellingen behouden.
  # ------------------------------------------------------------------
  config.winrm.transport = :plaintext
  config.winrm.basic_auth_only = true
  config.winrm.retry_limit = 60
  config.winrm.retry_delay = 10

  # Maximale wachttijd voor het opstarten van een VM.
  config.vm.boot_timeout = 600

  # ==================================================================
  # Server 1 — Domeincontroller, primaire DNS en later IIS
  # ==================================================================
  config.vm.define "server1" do |server1|

    server1.vm.box = "gusztavvargadr/windows-server-2025-standard-core"
    server1.vm.box_version = "2607.0.0"

    server1.vm.network "private_network",
      ip: "192.168.25.10",
      auto_config: false

    server1.vm.hostname = "server1"

    server1.vm.provider "virtualbox" do |vb|
      vb.name = "server1"
      vb.customize ["modifyvm", :id, "--groups", "/WS2"]
      vb.memory = "2048"
      vb.cpus = "2"
    end

    # 1. Host-Only IP instellen.
    server1.vm.provision "shell",
      path: "scripts/configure-network.ps1",
      args: "-IPAddress 192.168.26.10"

    server1.vm.provision "dns-registration",
      type: "shell",
      path: "scripts/configure-dns-registration.ps1",
      args: "-Mode Server"

    # 2. Domeincontroller-promotie.
    # Let op: reboot: true kan ook bij herprovisioning herstarten,
    # zelfs wanneer het script de promotie zelf overslaat.
    server1.vm.provision "shell",
      path: "scripts/server1/promote-dc.ps1",
      args: "-DomainName WS26-JD.hogent -DomainNetbiosName WS26-JD -SafeModePassword JouwSterkWachtwoord123!",
      reboot: true

    # 3. Bevestigen dat WinRM na de reboot opnieuw bereikbaar is.
    server1.vm.provision "shell",
      inline: "Write-Output 'server1 is terug online na domain controller promotie.'"

    # 4. OU-structuur en gebruikers aanmaken.
    server1.vm.provision "ad-users",
      type: "shell",
      path: "scripts/server1/create-ous-users.ps1"

    # 5. Primaire DNS configureren.
    server1.vm.provision "dns-primary",
      type: "shell",
      path: "scripts/server1/configure-dns-server1.ps1"

  end

  # ==================================================================
  # Server 2 — Secundaire DNS, geen domeincontroller
  # ==================================================================
  config.vm.define "server2" do |server2|

    server2.vm.box = "gusztavvargadr/windows-server-2025-standard-core"
    server2.vm.box_version = "2607.0.0"

    server2.vm.network "private_network",
      ip: "192.168.25.20",
      auto_config: false

    server2.vm.hostname = "server2"

    server2.vm.provider "virtualbox" do |vb|
      vb.name = "server2"
      vb.customize ["modifyvm", :id, "--groups", "/WS2"]
      vb.memory = "2048"
      vb.cpus = "2"
    end

    # 1. Host-Only IP instellen.
    server2.vm.provision "shell",
      path: "scripts/configure-network.ps1",
      args: "-IPAddress 192.168.26.20"

    server2.vm.provision "dns-registration",
      type: "shell",
      path: "scripts/configure-dns-registration.ps1",
      args: "-Mode Server"

    # 2. Secundaire DNS configureren.
    server2.vm.provision "dns-secondary",
      type: "shell",
      path: "scripts/server2/03-dns-secondary.ps1",
      args: "-PrimaryIP 192.168.26.10 -SecondaryIP 192.168.26.20 -DomainName WS26-JD.hogent"

  end

  # ==================================================================
  # Server 3 — Later Certification Authority en DHCP
  # ==================================================================
  config.vm.define "server3" do |server3|

    server3.vm.box = "gusztavvargadr/windows-server-2025-standard-core"
    server3.vm.box_version = "2607.0.0"

    server3.vm.network "private_network",
      ip: "192.168.25.30",
      auto_config: false

    server3.vm.hostname = "server3"

    server3.vm.provider "virtualbox" do |vb|
      vb.name = "server3"
      vb.customize ["modifyvm", :id, "--groups", "/WS2"]
      vb.memory = "2048"
      vb.cpus = "2"
    end

    # Host-Only IP instellen.
    server3.vm.provision "shell",
      path: "scripts/configure-network.ps1",
      args: "-IPAddress 192.168.26.30"

    server3.vm.provision "dns-registration",
      type: "shell",
      path: "scripts/configure-dns-registration.ps1",
      args: "-Mode Server"
  end

  # ==================================================================
  # Client — Windows 11 Enterprise, later RSAT en domain join
  # ==================================================================
  config.vm.define "client" do |client|

    client.vm.box = "gusztavvargadr/windows-11-25h2-enterprise"
    client.vm.box_version = "2607.1.0"

    client.vm.network "private_network",
      ip: "192.168.25.40",
      auto_config: false

    client.vm.hostname = "client"

    client.vm.provider "virtualbox" do |vb|
      vb.name = "client"
      vb.customize ["modifyvm", :id, "--groups", "/WS2"]
      vb.memory = "2048"
      vb.cpus = "2"
    end

    # DNS-registratie uitschakelen op beide clientinterfaces.
    client.vm.provision "dns-registration",
      type: "shell",
      path: "scripts/configure-dns-registration.ps1",
      args: "-Mode Client"

    # De Host-Only interface krijgt later een adres via Windows DHCP.
    # DHCP-clientconfiguratie, RSAT en domain join zijn nog toe te voegen.

  end
end