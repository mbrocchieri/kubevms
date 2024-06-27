#!/bin/bash

set -e

vagrant destroy -f
vagrant plugin install vagrant-disksize
vagrant up

vagrant ssh controlplane -c "/vagrant/scripts/post_install.sh"
