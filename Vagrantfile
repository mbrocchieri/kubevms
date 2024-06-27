require "yaml"

dir = File.dirname(File.expand_path(__FILE__))
configs = YAML.load_file "#{dir}/config.yaml"

Vagrant.configure("2") do |config|
    config.ssh.insert_key = false

    config.vm.define "controlplane" do |master|
        master.vm.box = configs["versions"]["imagebox"]
        master.vm.network "private_network", ip: "192.168.56.10"
        master.vm.hostname = "controlplane"
        master.vm.provider "virtualbox" do |virtualbox|
            virtualbox.memory = configs["controlplane"]["memory"]
        end
        master.vm.provision "shell",
          env: {
            "IP_REGISTRY" => configs["registry"]["ip"],
            "IP_STORAGE" => configs["storage"]["ip"]
          },
          path: "scripts/initenv.sh"
        master.vm.provision "shell", path: "scripts/docker.sh"
        master.vm.provision "shell",
          env: {
            "KUBERNETES_VERSION" => configs["versions"]["kubernetes"]
          },
          path: "scripts/kubecommon.sh"
        master.vm.provision "shell",
          env: {
            "KUBERNETES_VERSION" => configs["versions"]["kubernetes"],
            "CALICO_VERSION" => configs["versions"]["calico"],
            "INGRESS_VERSION" => configs["versions"]["ingress"],
            "HELM_VERSION" => configs["versions"]["helm"]
          },
          path: "scripts/controlplane.sh"
    end

    (1..configs["workers"]["count"]).each do |i|
        config.vm.define "node-#{i}" do |node|
            node.vm.box = configs["versions"]["imagebox"]
            node.vm.network "private_network", ip: "192.168.56.#{i + 10}"
            node.vm.hostname = "node-#{i}"
            node.vm.provider "virtualbox" do |virtualbox|
                virtualbox.memory = configs["controlplane"]["memory"]
            end
            node.vm.provision "shell", path: "scripts/initenv.sh",
              env: {
                "IP_REGISTRY" => configs["registry"]["ip"],
                "IP_STORAGE" => configs["storage"]["ip"]
              }
            node.vm.provision "shell", path: "scripts/docker.sh"
            node.vm.provision "shell",
              env: {
                "KUBERNETES_VERSION" => configs["versions"]["kubernetes"]
              },
              path: "scripts/kubecommon.sh"
            node.vm.provision "shell", path: "scripts/node.sh"
        end
    end

    config.vm.define "storage"  do |nfs|
        nfs.vm.box = configs["versions"]["imagebox"]
        nfs.vm.hostname = "storage"
        nfs.vm.network "private_network", ip: configs["storage"]["ip"]
        nfs.disksize.size = '200GB'

        nfs.vm.provision "shell", privileged: true, env: {"HOSTNAME" => nfs.vm.hostname}, inline: <<-SHELL
          apt-get update
          apt-get install -y nfs-kernel-server
          echo "/opt 192.168.56.0/24(rw,sync,no_root_squash,no_all_squash)" >> /etc/exports

          for SERVICES in rpcbind nfs-server; do
            systemctl enable $SERVICES
            systemctl restart $SERVICES
          done
      SHELL
    end

    if configs['registry']['enabled']
        config.vm.define "registry" do |registry|
            registry.vm.box = configs["versions"]["imagebox"]
            registry.vm.network "private_network", ip: configs["registry"]["ip"]
            registry.vm.hostname = "registry"
            registry.vm.provision "shell", path: "scripts/docker.sh"
            registry.vm.provision "shell", path: "scripts/dockerregistry.sh"
        end
    end
end
