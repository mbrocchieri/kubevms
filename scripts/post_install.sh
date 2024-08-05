#!/bin/bash

IP_BASE=$(yq -j .network.ip_range /vagrant/config.yaml)
POD_CIRD=$(yq -j .network.pod_cird /vagrant/config.yaml)
INGRESS_VERSION=$(yq -j .versions.ingress /vagrant/config.yaml)
CNI=$(yq -j .cni /vagrant/config.yaml)
LOADBALANCER=$(yq -j .loadbalancer /vagrant/config.yaml)

# install loadbalancer
if [ "$LOADBALANCER" == "purelb" ]
then
helm repo add purelb https://gitlab.com/api/v4/projects/20400619/packages/helm/stable
helm repo update
helm install --create-namespace --namespace=purelb purelb purelb/purelb
echo "
apiVersion: purelb.io/v1
kind: ServiceGroup
metadata:
  name: default
  namespace: purelb
spec:
  local:
    v4pools:
    - subnet: 172.30.200.0/24
      pool: 172.30.200.155-172.30.200.160
      aggregation: /32
" | kubectl create -f -
fi

# Metallb
if [ "$LOADBALANCER" == "metallb" ]
then
kubectl get configmap kube-proxy -n kube-system -o yaml | \
sed -e "s/strictARP: false/strictARP: true/" | \
kubectl apply -f - -n kube-system
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.5/config/manifests/metallb-native.yaml
for pod in $(kubectl get pods -n metallb-system | grep -v NAME | awk '{print $1}')
do
  kubectl wait --for=condition=Ready pod/$pod -n metallb-system
done
#helm repo add metallb https://metallb.github.io/metallb
#helm install metallb metallb/metallb
echo "
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: first-pool
  namespace: metallb-system
spec:
  addresses:
  - ${IP_BASE}.11/32
" | kubectl create -f -
fi

REGISTRY_CERTS=~/registry/certs
REGISTRY_AUTH=~/registry/auth
REGISTRY_PASSWORD=password
REGISTRY_NAMESPACE=registry
DOMAIN=$(yq -j .host /vagrant/config.yaml)
REGISTRY_DOMAIN=$(yq -j .registry.subdomain /vagrant/config.yaml).${DOMAIN}

# Install NGINX Ingress Controller
# helm upgrade --install ingress-nginx ingress-nginx \
#   --repo https://kubernetes.github.io/ingress-nginx \
#   --namespace ingress --create-namespace
# ????
# kubectl delete -A ValidatingWebhookConfiguration ingress-nginx-admission

helm pull oci://ghcr.io/nginxinc/charts/nginx-ingress --untar --version ${INGRESS_VERSION}
cd nginx-ingress
kubectl apply -f crds/
cd ..
helm install nginx-ingress oci://ghcr.io/nginxinc/charts/nginx-ingress --version ${INGRESS_VERSION} --set controller.service.externalTrafficPolicy=Cluster
# --create-namespace --namespace=ingress
#rm -fr nginx-ingress

# kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.11.1/deploy/static/provider/baremetal/deploy.yaml
# INGRESS_CONTROLLER_POD=$(kubectl get pods -n ingress-nginx | grep controller | awk '{print $1}')
# kubectl wait --for=jsonpath='{.status.phase}'=Running pod/$INGRESS_CONTROLLER_POD -n ingress-nginx --timeout=400s
# 
# echo "
# apiVersion: v1
# kind: Service
# metadata:
#   name: ingress-nginx-controller-lb
#   namespace: ingress-nginx
# spec:
#   externalTrafficPolicy: Cluster
#   internalTrafficPolicy: Cluster
#   ports:
#   - appProtocol: http
#     name: http
#     port: 80
#     protocol: TCP
#     targetPort: http
#   - appProtocol: https
#     name: https
#     port: 443
#     protocol: TCP
#     targetPort: https
#   selector:
#     app.kubernetes.io/component: controller
#     app.kubernetes.io/instance: ingress-nginx
#     app.kubernetes.io/name: ingress-nginx
#   sessionAffinity: None
#   type: LoadBalancer" | kubectl create -f -

# install csi-driver-nfs to use pvs
helm repo add csi-driver-nfs https://raw.githubusercontent.com/kubernetes-csi/csi-driver-nfs/master/charts
helm install csi-driver-nfs csi-driver-nfs/csi-driver-nfs --namespace kube-system --version v4.7.0
echo "
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: nfs-csi
  annotations:
    storageclass.kubernetes.io/is-default-class: \"true\"
provisioner: nfs.csi.k8s.io
parameters:
  server: storage
  share: /shared/kubernetes
  mountPermissions: '777'" | kubectl create -f -

mkdir -p ${REGISTRY_CERTS}
mkdir -p ${REGISTRY_AUTH}

#openssl req -x509 -newkey rsa:4096 -days 365 -nodes -sha256 -keyout ${REGISTRY_CERTS}/tls.key -out ${REGISTRY_CERTS}/tls.crt -subj "/CN=docker-registry" -addext "subjectAltName = DNS:docker-registry"
openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout ${REGISTRY_CERTS}/tls.key -out ${REGISTRY_CERTS}/tls.crt -subj "/CN=${REGISTRY_DOMAIN}/O=${REGISTRY_DOMAIN}" -addext "subjectAltName = DNS:${REGISTRY_DOMAIN}"
# docker run --rm --entrypoint htpasswd registry:2.6.2 -Bbn user ${REGISTRY_PASSWORD} > ${REGISTRY_AUTH}/htpasswd
REGISTRY_TLS_SECRET=registry-tls
kubectl create namespace ${REGISTRY_NAMESPACE}
kubectl create secret -n ${REGISTRY_NAMESPACE} tls $REGISTRY_TLS_SECRET --cert=${REGISTRY_CERTS}/tls.crt --key=${REGISTRY_CERTS}/tls.key
sudo cp ${REGISTRY_CERTS}/tls.crt /vagrant/ca.crt
sudo cp ${REGISTRY_CERTS}/tls.crt /usr/local/share/ca-certificates/ca.crt
sudo update-ca-certificates
# kubectl create secret -n ${REGISTRY_NAMESPACE} generic auth-secret --from-file=${REGISTRY_AUTH}/htpasswd
# cd
# kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.15.1/cert-manager.yaml

echo "
apiVersion: apps/v1
kind: Deployment
metadata:
  name: docker-registry
  namespace: $REGISTRY_NAMESPACE
spec:
  replicas: 1
  selector:
    matchLabels:
      app: docker-registry
  template:
    metadata:
      labels:
        app: docker-registry
    spec:
      containers:
        - name: docker-registry
          image: registry:2.6.2
          env:
            - name: REGISTRY_HTTP_ADDR
              value: \":5000\"
            - name: REGISTRY_STORAGE_FILESYSTEM_ROOTDIRECTORY
              value: \"/var/lib/registry\"
          ports:
          - name: http
            containerPort: 5000
          volumeMounts:
          - name: image-store
            mountPath: \"/var/lib/registry\"
      volumes:
        - name: image-store
          emptyDir: {}
" | kubectl create -f -

echo "
kind: Service
apiVersion: v1
metadata:
  name: docker-registry
  namespace: $REGISTRY_NAMESPACE
  labels:
    app: docker-registry
spec:
  selector:
    app: docker-registry
  ports:
  - name: http
    port: 5000
    targetPort: 5000
" | kubectl create -f -

# https://github.com/kubernetes/ingress-nginx/tree/main/docs/examples/docker-registry
echo "
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: docker-registry
  namespace: $REGISTRY_NAMESPACE
  annotations:
    nginx.ingress.kubernetes.io/proxy-body-size: \"0\"
    nginx.ingress.kubernetes.io/proxy-read-timeout: \"600\"
    nginx.ingress.kubernetes.io/proxy-send-timeout: \"600\"
    kubernetes.io/tls-acme: 'true'
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - registry.kube.lab
    secretName: $REGISTRY_TLS_SECRET
  rules:
  - host: registry.kube.lab
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: docker-registry
            port:
              number: 5000
" | kubectl create -f -

# argocd https://artifacthub.io/packages/helm/argo/argo-cd
# helm repo add argo https://argoproj.github.io/argo-helm
# echo "
# global:
#   domain: ${DOMAIN}
# 
# configs:
#   params:
#     server.insecure: true
# 
# server:
#   ingress:
#     enabled: true
#     ingressClassName: nginx
#     path: /argocd
#     pathType: Prefix" > ~/argocd.values.yaml
# helm install argo-cd argo/argo-cd --version 7.3.6 --values ~/argocd.values.yaml --create-namespace --namespace=argocd
# # kubectl create ns argocd
# # kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
# 
# sleep 30s
# 
# ARGOCD_POD=$(kubectl get pods -n argocd | grep "argocd-server" | awk '{print $1}')
# kubectl wait --for=condition=Ready pod/$ARGOCD_POD -n argocd --timeout=600s
# 
# echo "ArgoCD"
# echo "login : admin"
# echo "password : $(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)"
