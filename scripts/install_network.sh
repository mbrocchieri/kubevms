#!/bin/bash

CNI=$(yq -j .cni /vagrant/config.yaml)

if [ "$CNI" == "calico" ]
then
  echo "install calico"
  CALICO_VERSION=$(yq -j .versions.calico /vagrant/config.yaml)
  # calico method 1
  kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v${CALICO_VERSION}/manifests/tigera-operator.yaml
  kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v${CALICO_VERSION}/manifests/custom-resources.yaml
  #
  # calico method 2
  #kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v${CALICO_VERSION}/manifests/calico.yaml
fi

if [ "$CNI" == "flannel" ]
then
  echo "install flannel"
  POD_CIRD=$(yq -j .network.pod_cird /vagrant/config.yaml)
  for node in $(kubectl get nodes | grep -v NAME | awk '{print $1}')
  do
    kubectl patch node ${node} -p "{\"spec\":{\"podCIDR\":\"${POD_CIRD}\"}}"
  done
  
  kubectl create ns kube-flannel
  kubectl label --overwrite ns kube-flannel pod-security.kubernetes.io/enforce=privileged
  
  helm repo add flannel https://flannel-io.github.io/flannel/
  helm install flannel --set podCidr="${POD_CIRD}" --set flannel.args="{--ip-masq,--kube-subnet-mgr,--iface=eth1}" --namespace kube-flannel flannel/flannel
fi
