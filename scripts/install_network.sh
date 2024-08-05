#!/bin/bash

CNI=$(yq -j .cni /vagrant/config.yaml)

if [ "$CNI" == "calico" ]
then
  echo "install calico"
  CALICO_VERSION=$(yq -j .versions.calico /vagrant/config.yaml)
  # calico method 1
  #kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v${CALICO_VERSION}/manifests/tigera-operator.yaml
  #kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v${CALICO_VERSION}/manifests/custom-resources.yaml
  #
  # calico method 2
  # according to https://docs.tigera.io/calico/latest/getting-started/kubernetes/self-managed-onprem/onpremises
  # pod_cird muste be 192.168.0.0/16 or update calico.yaml
  kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v${CALICO_VERSION}/manifests/calico.yaml

  CALICO_NODE_POD_NAME=""
  while [ "$CALICO_NODE_POD_NAME" == "" ]
  do
    CALICO_NODE_POD_NAME=$(kubectl get pod -n kube-system | grep calico-node | awk '{print $1}')
    sleep 1s
  done
  kubectl wait --for=jsonpath='{.status.phase}'=Running pod/$CALICO_NODE_POD_NAME -n kube-system --timeout=400s
  # Workarround to have POD_CIRD IP
  kubectl rollout restart deployment --namespace kube-system calico-kube-controllers
  sleep 10s
  CALICO_KUBE_CONTROL_POD=$(kubectl get pod -n kube-system | grep calico-kube-controllers | awk '{print $1}')
  kubectl wait --for=jsonpath='{.status.phase}'=Running pod/$CALICO_KUBE_CONTROL_POD -n kube-system --timeout=400s

  LOADBALANCER=$(yq -j .loadbalancer /vagrant/config.yaml)
  if [ "$LOADBALANCER" == "purelb" ]
  then
echo "apiVersion: crd.projectcalico.org/v1
kind: IPPool
metadata:
  name: purelb-ipv4
  namespace: kube-system
spec:
  cidr: 172.30.200.0/24
  disabled: true
" | kubectl create -f -
  fi
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

# To have POD_CIRD IP for coredns
kubectl rollout restart deployment coredns --namespace kube-system
