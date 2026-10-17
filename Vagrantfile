
# Homework: High Availability React Application Infrastructure
# Four Ubuntu 24.04 VMs on one VirtualBox host-only network.

Vagrant.configure("2") do |config|
  config.vm.box = "bento/ubuntu-24.04"
  config.vm.boot_timeout = 600

  machines = [
    { name: "lb-01",  ip: "192.168.56.10", memory: 512,  cpus: 1 },
    { name: "lb-02",  ip: "192.168.56.11", memory: 512,  cpus: 1 },
    { name: "web-01", ip: "192.168.56.20", memory: 1024, cpus: 1 },
    { name: "web-02", ip: "192.168.56.21", memory: 1024, cpus: 1 }
  ]

  machines.each do |machine|
    config.vm.define machine[:name] do |node|
      node.vm.hostname = machine[:name]

      # Host-only network + default NAT adapter.
      node.vm.network "private_network", ip: machine[:ip]

      node.vm.provider "virtualbox" do |vb|
        vb.name = "ha-react-#{machine[:name]}"
        vb.memory = machine[:memory]
        vb.cpus = machine[:cpus]
      end

      # Install basic administration tools.
      node.vm.provision "shell", inline: <<-SHELL
        set -e
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -qq
        apt-get install -y curl ca-certificates iputils-ping
      SHELL
    end
  end
end
