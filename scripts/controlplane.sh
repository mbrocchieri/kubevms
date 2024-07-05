#!/bin/bash

set -e

echo 'source <(kubectl completion bash)' >>/home/vagrant/.bashrc
echo 'alias k=kubectl' >>/home/vagrant/.bashrc
echo 'complete -o default -F __start_kubectl k' >>/home/vagrant/.bashrc

sudo kubeadm config images pull
sudo kubeadm init --apiserver-advertise-address="${IP_BASE}.10" --apiserver-cert-extra-sans="${IP_BASE}.10" --node-name controlplane --pod-network-cidr=${POD_CIRD} --service-cidr=${SERVICE_CIRD}
sudo mkdir -p /home/vagrant/.kube/
sudo cp -i /etc/kubernetes/admin.conf /home/vagrant/.kube/config
sudo chown -R vagrant:vagrant /home/vagrant/.kube/config

while ! nc -z localhost 6443
do
  sleep 1s
done

kubeadm token create --print-join-command > /vagrant/join_command

curl -fsSL -o helm.tar.gz https://get.helm.sh/helm-v${HELM_VERSION}-linux-amd64.tar.gz
tar -zxf helm.tar.gz
mv linux-amd64/helm /usr/local/bin/helm
