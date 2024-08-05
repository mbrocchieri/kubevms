#!/bin/bash

set -e

CONTOLPLANE_NAME=controlplane

vagrant destroy -f
vagrant plugin install vagrant-disksize
vagrant up $CONTOLPLANE_NAME
vagrant ssh $CONTOLPLANE_NAME -c "/vagrant/scripts/install_network.sh"

WORKERS_COUNT=$(yq -j .workers.count config.yaml)
for i in $(seq $WORKERS_COUNT)
do
  vagrant up node$i
  vagrant ssh $CONTOLPLANE_NAME -c "/vagrant/scripts/post_install_node.sh node$i"
done

vagrant up

vagrant ssh $CONTOLPLANE_NAME -c "/vagrant/scripts/post_install.sh"

# for i in $(seq $WORKERS_COUNT)
# do
#   vagrant ssh node$i -c "sudo cp /vagrant/ca.crt /usr/local/share/ca-certificates/"
#   vagrant ssh node$i -c "sudo update-ca-certificates"
#   vagrant ssh node$i -c "sudo systemctl restart crio"
#   vagrant ssh node$i -c "sudo systemctl restart kubelet"
# done
