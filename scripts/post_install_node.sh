#!/bin/bash

CNI=$(yq -j .cni /vagrant/config.yaml)
if [ "$CNI" == "flannel" ]
then
  POD_CIRD=$(yq -j .network.pod_cird /vagrant/config.yaml)
  kubectl patch node $1 -p "{\"spec\":{\"podCIDR\":\"${POD_CIRD}\"}}"
fi
