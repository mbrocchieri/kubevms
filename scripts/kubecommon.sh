#!/bin/bash

set -e

# Install kubernetes
# sudo cp /vagrant/files/config.toml /etc/containerd/config.toml

sudo mkdir -p -m 755 /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v${KUBERNETES_VERSION}/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
sudo chmod 644 /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v${KUBERNETES_VERSION}/deb/ /" | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo chmod 644 /etc/apt/sources.list.d/kubernetes.list   # helps tools such as command-not-found to work correctly

sudo apt-get update
sudo apt-get install -y kubectl kubelet kubeadm jq yq

cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
overlay
br_netfilter
EOF
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.ipv4.ip_forward                 = 1
EOF
#net.bridge.bridge-nf-call-ip6tables = 1

sudo modprobe overlay
sudo modprobe br_netfilter

sudo sysctl --system
echo "KUBELET_EXTRA_ARGS=--node-ip=$(ip -f inet addr show eth1 | awk '/inet / {print $2}' | awk -F / '{print $1}')" | sudo tee /etc/default/kubelet
sudo chmod 600 /etc/default/kubelet

#sudo systemctl restart containerd

sudo systemctl daemon-reload
sudo systemctl enable --now kubelet
sudo systemctl restart kubelet

sudo apt-mark hold kubelet kubectl kubeadm

sudo swapoff -a
