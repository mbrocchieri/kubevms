#!/bin/bash

set -e

echo 'source <(kubectl completion bash)' >>/home/vagrant/.bashrc
echo 'alias k=kubectl' >>/home/vagrant/.bashrc
echo 'complete -o default -F __start_kubectl k' >>/home/vagrant/.bashrc

sudo kubeadm config images pull
sudo kubeadm init --apiserver-advertise-address="192.168.56.10" --apiserver-cert-extra-sans="192.168.56.10"  --node-name controlplane --pod-network-cidr=192.168.0.0/16
sudo mkdir -p /home/vagrant/.kube/
sudo cp -i /etc/kubernetes/admin.conf /home/vagrant/.kube/config
sudo chown -R vagrant:vagrant /home/vagrant/.kube/config

while ! nc -z localhost 6443
do
  sleep 1s
done

kubeadm token create --print-join-command > /vagrant/join_command

sudo -u vagrant kubectl get nodes
sudo -u vagrant kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v${CALICO_VERSION}/manifests/tigera-operator.yaml
sudo -u vagrant kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v${CALICO_VERSION}/manifests/custom-resources.yaml

# install loadbalancer
sudo -u vagrant kubectl get configmap kube-proxy -n kube-system -o yaml | sed -e "s/strictARP: false/strictARP: true/" | sudo -u vagrant kubectl apply -f - -n kube-system
sudo -u vagrant kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.5/config/manifests/metallb-native.yaml
for pod in $(sudo -u vagrant kubectl get pods -n metallb-system | grep -v NAME | awk '{print $1}')
do
  sudo -u vagrant kubectl wait --for=condition=Ready pod/$pod -n metallb-system
done
curl -fsSL -o helm.tar.gz https://get.helm.sh/helm-v${HELM_VERSION}-linux-amd64.tar.gz
tar -zxf helm.tar.gz
mv linux-amd64/helm /usr/local/bin/helm

# Install NGINX Ingress Controller
sudo -u vagrant helm pull oci://ghcr.io/nginxinc/charts/nginx-ingress --untar --version ${INGRESS_VERSION}
cd nginx-ingress
sudo -u vagrant kubectl apply -f crds
cd -
sudo -u vagrant helm install nginx-ingress oci://ghcr.io/nginxinc/charts/nginx-ingress --version ${INGRESS_VERSION} --set controller.service.externalTrafficPolicy=Cluster
rm -fr nginx-ingress

# install csi-driver-nfs to use pvs
sudo -u vagrant helm repo add csi-driver-nfs https://raw.githubusercontent.com/kubernetes-csi/csi-driver-nfs/master/charts
sudo -u vagrant helm install csi-driver-nfs csi-driver-nfs/csi-driver-nfs --namespace kube-system --version v4.7.0
