#!/bin/bash



for f in /vagrant/kubeinit/*
do
  kubectl create -f ${f}
done
# argocd
kubectl create ns argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

sleep 30s

kubectl get nodes
kubectl get ns
ARGOCD_POD=$(kubectl get pods -n argocd | grep "argocd-server" | awk '{print $1}')
kubectl wait --for=condition=Ready pod/$ARGOCD_POD -n argocd --timeout=600s

echo "ArgoCD"
echo "login : admin"
echo "password : $(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)"
