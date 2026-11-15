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
# Labcredentials staan bewust in deze configuratie.
# Gebruik deze wachtwoorden nergens buiten deze labomgeving.
#
# Alle VM's starten:
#   vagrant up
#
# Alleen primaire DNS opnieuw configureren:
#   vagrant provision server1 --provision-with dns-primary
#
# Alleen secundaire DNS opnieuw configureren:
#   vagrant provision server2 --provision-with dns-secondary
#
# Alleen server3 aan het domein toevoegen/controleren:
#   vagrant provision server3 --provision-with server3-domain
#
# CA en Web Enrollment op server3 installeren/controleren:
#   vagrant provision server3 --provision-with server3-ca
#
# Alleen HTTPS configureren nadat de templatepermissies gereed zijn:
#   vagrant provision server3 --provision-with server3-web-https
#
# Let op: deze losse opdrachten voeren niet automatisch de volledige
# CA-afhankelijke onderhoudsketen uit. Zie de deploymentdocumentatie.
#
# Alleen DHCP op server3 installeren/configureren:
#   vagrant provision server3 --provision-with server3-dhcp
# Provisioningbeleid:
# - Standaard: installatie/configuratie tijdens de eerste uitrol.
# - always: firewallbeleid, rootcertificaatpublicatie en clientcontrole
#   opnieuw uitvoeren bij Vagrant up/reload.
# - never: afhankelijkheidsgevoelige CA-stappen niet rechtstreeks
#   tijdens de gewone machineprovisioning uitvoeren.
#   De clientprovisioner lab-finalize roept deze automatisch
#   in de juiste volgorde aan.
#   Gerichte onderhoudsopdrachten blijven mogelijk vanaf de host.
# Voor gericht onderhoud:
#   vagrant provision <machine> --provision-with <provisionernaam>
#
# Een volledige herprovisioning kan ook domeinjoin-/promotieprovisioners
# met reboot: true opnieuw uitvoeren.

require "tempfile"

require Vagrant.source_root.join(
  "plugins/provisioners/shell/provisioner"
).to_s

module WS2AutomaticFinalization
  class Provisioner < Vagrant.plugin("2", :provisioner)
    def provision
      server1 = @machine.env.machine(
        :server1,
        @machine.provider_name
      )

      server3 = @machine.env.machine(
        :server3,
        @machine.provider_name
      )

      [server1, server3].each do |machine|
        unless machine.state.id == :running
          raise "#{machine.name} draait niet. Start de volledige omgeving."
        end

        unless machine.communicate.ready?
          raise "#{machine.name} is niet bereikbaar via Vagrant."
        end
      end

      run_shell(server1, "webserver-template")
      run_shell(server3, "server3-web-https")
      run_shell(server1, "ca-trust-gpo")
      run_shell(server1, "server1-trust-root-ca")
      run_shell(server1, "server1-verify-web-enrollment")

      # Het publieke referentiecertificaat overbrengen.
      # Dit importeert niets in de vertrouwde certificaatopslag.
      Tempfile.create(["ws2-current-root-", ".cer"]) do |file|
        local_path = file.path
        file.close

        server3.communicate.download(
          "C:/LabCertificates/WS26-JD-Root-CA.cer",
          local_path
        )

        @machine.communicate.upload(
          local_path,
          "C:/Windows/Temp/WS2-current-root-ca.cer"
        )
      end

      run_shell(@machine, "client-verify-ca")

      @machine.ui.success(
        "Automatische CA-naverwerking en clientcontrole geslaagd."
      )
    end

    private

    def run_shell(machine, name)
      definition = machine.config.vm.provisioners.find do |item|
        item.name.to_s == name
      end

      unless definition && definition.type.to_s == "shell"
        raise "Shell-provisioner ontbreekt: #{machine.name}/#{name}"
      end

      @machine.ui.info(
        "CA-naverwerking: #{machine.name}/#{name}"
      )

      VagrantPlugins::Shell::Provisioner.new(
        machine,
        definition.config
      ).provision
    end
  end

  class Plugin < Vagrant.plugin("2")
    name "ws2-automatic-finalization"

    provisioner(:ws2_finalize) do
      Provisioner
    end
  end
end

Vagrant.configure("2") do |config|

  # ------------------------------------------------------------------
  # Labconfiguratie.
  # ------------------------------------------------------------------
  domain_name = "WS26-JD.hogent"
  domain_netbios_name = "WS26-JD"

  # Voorkom dat vagrant-vbguest Guest Additions probeert bij te werken.
  # De Guest Additions in de box (7.2.14) werken correct voor dit lab.
  if Vagrant.has_plugin?("vagrant-vbguest")
    config.vbguest.auto_update = false
    config.vbguest.no_install = true
    config.vbguest.no_remote  = true
  end

  # DSRM-herstelwachtwoord van de domeincontroller.
  dsrm_password = "JouwSterkWachtwoord123!"

  # Domeinaccount voor de server3-domeinjoin.
  # Dit is een ander credentialdoel dan het DSRM-wachtwoord.
  # Controleer dat deze waarde daadwerkelijk bij Administrator hoort.
  domain_admin_user = "#{domain_netbios_name}\\Administrator"
  domain_admin_password = "JouwSterkWachtwoord123!"
  # ssh -l "WS26-JD\Administrator" -o PreferredAuthentications=password -o PubkeyAuthentication=no -o PasswordAuthentication=yes 192.168.26.30
  # ssh -p 2222 -l "WS26-JD\Administrator" -o PreferredAuthentications=password -o PubkeyAuthentication=no -o PasswordAuthentication=yes 127.0.0.1

  # ------------------------------------------------------------------
  # WinRM-workaround voor de huidige labomgeving na AD-promotie.
  # Bestaande werkende instellingen behouden.
  # ------------------------------------------------------------------
  config.winrm.transport = :plaintext
  config.winrm.basic_auth_only = true
  config.winrm.retry_limit = 60
  config.winrm.retry_delay = 10

  # Maximale wachttijd voor het opstarten van een VM.
  config.vm.boot_timeout = 1200

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
      vb.memory = "2048"
      vb.cpus = "2"
    end

    # 1. Host-Only IP instellen.
    server1.vm.provision "server1-network",
      type: "shell",
      path: "scripts/configure-network.ps1",
      args: "-IPAddress 192.168.26.10"

    # 2. DNS-registratie configureren.
    server1.vm.provision "dns-registration",
      type: "shell",
      path: "scripts/configure-dns-registration.ps1",
      args: "-Mode Server"

    # 3. Domeincontroller-promotie.
    # Let op: reboot: true kan ook bij herprovisioning herstarten,
    # zelfs wanneer het script de promotie zelf overslaat.
    server1.vm.provision "shell",
      path: "scripts/server1/promote-dc.ps1",
      args: [
        "-DomainName", domain_name,
        "-DomainNetbiosName", domain_netbios_name,
        "-SafeModePassword", dsrm_password
      ],
      reboot: true

    # 4. Bevestigen dat WinRM na de reboot opnieuw bereikbaar is.
    server1.vm.provision "shell",
      inline: "Write-Output 'server1 is terug online na domain controller promotie.'"

    # Domein-Administratorwachtwoord expliciet instellen voor het lab.
    server1.vm.provision "domain-admin",
      type: "shell",
      path: "scripts/server1/configure-domain-admin.ps1",
      args: [
        "-DomainAdminPassword", domain_admin_password
      ],
      privileged: true

    # 5. OU-structuur en gebruikers aanmaken.
    server1.vm.provision "ad-users",
      type: "shell",
      path: "scripts/server1/create-ous-users.ps1"

    # Templatepermissies configureren nadat server3 domeinlid is.
    server1.vm.provision "webserver-template",
      type: "shell",
      path: "scripts/server1/configure-webserver-template.ps1",
      args: [
        "-DomainAdminUser", domain_admin_user,
        "-DomainAdminPassword", domain_admin_password
      ],
      privileged: true,
      run: "never"

    # 6. Primaire DNS configureren.
    server1.vm.provision "dns-primary",
      type: "shell",
      path: "scripts/server1/configure-dns-server1.ps1"

    server1.vm.provision "server1-iis",
      type: "shell",
      path: "scripts/server1/iis.ps1",
      args: [
        "-DomainName", domain_name
      ],
      privileged: true

    # CA-vertrouwen via GPO.
    # Automatisch aangeroepen door lab-finalize nadat server3 klaar is.    
    server1.vm.provision "ca-trust-gpo",
      type: "shell",
      path: "scripts/server1/configure-ca-trust-gpo.ps1",
      args: [
        "-DomainName", domain_name,
        "-CAConfig", "server3.#{domain_name}\\WS26-JD-Root-CA",
        "-CACommonName", "WS26-JD-Root-CA"
      ],
      privileged: true,
      run: "never"

    server1.vm.provision "server1-trust-root-ca",
    type: "shell",
    run: "never",
    path: "scripts/server1/trust-root-ca.ps1"

    server1.vm.provision "server1-verify-web-enrollment",
    type: "shell",
    run: "never",
    path: "scripts/server1/verify-web-enrollment.ps1",
    env: {
      "WS26_ADMIN_PASSWORD" => "JouwSterkWachtwoord123!"
    }

    # Firewallbeleid opnieuw toepassen bij Vagrant up/reload
    # volgens de ingestelde run: "always".
    server1.vm.provision "server1-firewall",
      type: "shell",
      path: "scripts/configure-firewall.ps1",
      args: ["-Machine", "server1"],
      privileged: true,
      run: "always"
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
      vb.memory = "2048"
      vb.cpus = "2"
    end

    # 1. Host-Only IP instellen.
    server2.vm.provision "server2-network",
      type: "shell",
      path: "scripts/configure-network.ps1",
      args: "-IPAddress 192.168.26.20"

    # 2. DNS-registratie configureren.
    server2.vm.provision "dns-registration",
      type: "shell",
      path: "scripts/configure-dns-registration.ps1",
      args: "-Mode Server"

    # Server2 aan het domein toevoegen en daarna herstarten.
    server2.vm.provision "server2-domain",
      type: "shell",
      path: "scripts/server2/join-domain.ps1",
      args: [
        "-DomainName", domain_name,
        "-OUPath", "OU=Servers,DC=WS26-JD,DC=hogent",
        "-DomainAdminUser", domain_admin_user,
        "-DomainAdminPassword", domain_admin_password
      ],
      privileged: true,
      reboot: true

    # 3. Secundaire DNS configureren.
    server2.vm.provision "dns-secondary",
      type: "shell",
      path: "scripts/server2/dns-secondary.ps1",
      args: [
        "-PrimaryIP", "192.168.26.10",
        "-SecondaryIP", "192.168.26.20",
        "-DomainName", domain_name
      ]

    # Firewallbeleid toepassen volgens run: "always".
    server2.vm.provision "server2-firewall",
      type: "shell",
      path: "scripts/configure-firewall.ps1",
      args: ["-Machine", "server2"],
      privileged: true,
      run: "always"
  end

  # ==================================================================
  # Server 3 — Certification Authority en DHCP
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
      vb.memory = "2048"
      vb.cpus = "2"
    end

    # 1. Host-Only IP instellen.
    server3.vm.provision "server3-network",
      type: "shell",
      path: "scripts/configure-network.ps1",
      args: "-IPAddress 192.168.26.30"

    # 2. DNS-registratie configureren.
    server3.vm.provision "dns-registration",
      type: "shell",
      path: "scripts/configure-dns-registration.ps1",
      args: "-Mode Server"

    # 3. Domeinjoin uitvoeren/controleren en daarna herstarten.
    # Server1, DNS en de Servers-OU moeten vooraf beschikbaar zijn.
    # Het script slaat de join over als server3 al domeinlid is.
    # reboot: true herstart ook wanneer het script de join overslaat.
    server3.vm.provision "server3-domain",
      type: "shell",
      path: "scripts/server3/join-domain.ps1",
      args: [
        "-DomainName", domain_name,
        "-OUPath", "OU=Servers,DC=WS26-JD,DC=hogent",
        "-DomainAdminUser", domain_admin_user,
        "-DomainAdminPassword", domain_admin_password
      ],
      privileged: true,
      reboot: true

    # 4. Enterprise Root CA en CA Web Enrollment installeren/configureren.
    # De certificaataanvraag en HTTPS-configuratie volgen apart,
    # nadat de templatepermissies op server1 zijn ingesteld.
    server3.vm.provision "server3-ca",
      type: "shell",
      path: "scripts/server3/ca.ps1",
      args: [
        "-DomainName", domain_name,
        "-DomainAdminUser", domain_admin_user,
        "-DomainAdminPassword", domain_admin_password,
        "-CACommonName", "WS26-JD-Root-CA"
      ],
      privileged: true

    # Automatisch aangeroepen door lab-finalize nadat de
    # templatepermissies op server1 zijn geconfigureerd.    
    server3.vm.provision "server3-web-https",
      type: "shell",
      path: "scripts/server3/configure-web-enrollment-https.ps1",
      args: [
        "-DomainName", domain_name,
        "-DomainAdminUser", domain_admin_user,
        "-DomainAdminPassword", domain_admin_password
      ],
      privileged: true,
      run: "never"

    # 5. DHCP installeren en configureren.
    # Het huidige script configureert:
    # - DHCP-serverrol en beheertools
    # - Scope 192.168.26.100 t/m 192.168.26.200
    # - Exclusion 192.168.26.151 t/m 192.168.26.200
    # - Optie 6: 192.168.26.10 en 192.168.26.20
    # - Optie 15: WS26-JD.hogent
    #
    # Geen routeroptie voor het interne Host-Only-netwerk.
    # Inclusief AD-autorisatie en binding aan de interne interface.
    server3.vm.provision "server3-dhcp",
      type: "shell",
      path: "scripts/server3/dhcp.ps1",
      args: [
        "-DomainAdminUser", domain_admin_user,
        "-DomainAdminPassword", domain_admin_password
      ],
      privileged: true

    # Firewallbeleid automatisch toepassen met run: "always".    
    server3.vm.provision "server3-firewall",
      type: "shell",
      path: "scripts/configure-firewall.ps1",
      args: ["-Machine", "server3"],
      privileged: true,
      run: "always"


    # Publicatie van het publieke rootcertificaat bij iedere
    # Vagrant up/reload opnieuw uitvoeren.
    server3.vm.provision "server3-publish-root-ca",
      type: "shell",
      run: "always",
      path: "scripts/server3/publish-root-ca.ps1"

    # CA-afhankelijke naverwerking gebeurt automatisch via lab-finalize
    # op de client, nadat de client aan het domein is toegevoegd.
    # Server1 en server3 moeten dan draaien en bereikbaar zijn.
    #
    # Volgorde:
    # 1. server1: webserver-template
    # 2. server3: server3-web-https
    # 3. server1: ca-trust-gpo
    # 4. server1: server1-trust-root-ca
    # 5. server1: server1-verify-web-enrollment
    # 6. actueel publiek CA-certificaat naar client overbrengen
    # 7. client: client-verify-ca
    #
    # Geen geneste Vagrant-opdrachten of after-up-triggers.  
  end

  # ==================================================================
  # Client — Windows 11 Enterprise, later RSAT en domeinjoin
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
      vb.memory = "2048"
      vb.cpus = "2"
    end

    # DNS-registratie uitschakelen op beide clientinterfaces.
    client.vm.provision "dns-registration",
      type: "shell",
      path: "scripts/configure-dns-registration.ps1",
      args: "-Mode Client"

    client.vm.provision "client-rsat",
      type: "shell",
      path: "scripts/client/install-rsat.ps1",
      privileged: true

    # De interne clientinterface hoort een adres via DHCP op server3
    # te ontvangen. DHCP en domein-DNS moeten vóór de clientjoin werken.
    # Firewallbeleid toepassen; provisioner staat op run: "always".
    client.vm.provision "client-firewall",
      type: "shell",
      path: "scripts/client/configure-client-firewall.ps1",
      privileged: true,
      run: "always"

    client.vm.provision "client-domain",
      type: "shell",
      path: "scripts/client/join-domain.ps1",
      args: [
        "-DomainName", domain_name,
        "-OUPath", "OU=Clients,DC=WS26-JD,DC=hogent",
        "-DomainController", "server1.#{domain_name}",
        "-DomainAdminUser", domain_admin_user,
        "-DomainAdminPassword", domain_admin_password
      ],
      privileged: true,
      reboot: true

    # CA-vertrouwen bij iedere Vagrant up/reload controleren.
    # Een mislukte controle moet zichtbaar tot een fout leiden.
    # Het actuele publieke CA-certificaat wordt door lab-finalize
    # automatisch van server3 opgehaald en naar de client gekopieerd.
    # verify-ca.ps1 bepaalt daaruit de verwachte thumbprint.
    # Geen handmatige thumbprintaanpassing nodig na een herbouw.
    # Deze controle wordt door lab-finalize aangeroepen.
    client.vm.provision "client-verify-ca",
      type: "shell",
      run: "never",
      privileged: true,
      path: "scripts/client/verify-ca.ps1",
      args: [
        "-ExpectedCertificatePath",
        "C:/Windows/Temp/WS2-current-root-ca.cer"
      ]

    # Automatische eindfase, nadat de client domeinlid is.
    client.vm.provision "lab-finalize",
      type: "ws2_finalize",
      run: "always"
  end

end