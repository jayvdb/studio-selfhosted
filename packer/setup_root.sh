#!/bin/bash

PS4='studio-selfhosted:setup_root.sh: '
set -eux
set -o pipefail

if [ "$EUID" -ne 0 ]
  then echo "Please run as root"
  exit
fi

export DEBIAN_FRONTEND=noninteractive

# Install K3s - script uploaded with packer
export K3S_VERSION="v1.25.7+k3s1"
export K3S_KUBECONFIG_MODE="644"
export INSTALL_K3S_VERSION="${K3S_VERSION}"
export INSTALL_K3S_SKIP_START="true"
export INSTALL_K3S_EXEC=""
export INSTALL_K3S_EXEC="$INSTALL_K3S_EXEC --disable=traefik"
export INSTALL_K3S_EXEC="$INSTALL_K3S_EXEC --kubelet-arg kube-reserved=cpu=500m,memory=1Gi,ephemeral-storage=1Gi"
export INSTALL_K3S_EXEC="$INSTALL_K3S_EXEC --kubelet-arg system-reserved=cpu=500m,memory=1Gi,ephemeral-storage=1Gi"
export INSTALL_K3S_EXEC="$INSTALL_K3S_EXEC --kubelet-arg eviction-hard=memory.available<0.5Gi,nodefs.available<10%"
sh /home/ubuntu/.studio_install/k3s.sh -
echo KUBECONFIG="/etc/rancher/k3s/k3s.yaml" >> /etc/environment

# Air-Gap Install https://docs.k3s.io/installation/airgap#prepare-the-images-directory-and-k3s-binary
mkdir -p /var/lib/rancher/k3s/agent/images/
curl "https://github.com/k3s-io/k3s/releases/download/${K3S_VERSION}/k3s-airgap-images-amd64.tar" -L -o /var/lib/rancher/k3s/agent/images/k3s-airgap-images-amd64.tar

# Install k9s
export K9S_VERSION=v0.27.3
cd /tmp
curl --silent -L https://github.com/derailed/k9s/releases/download/${K9S_VERSION}/k9s_Linux_amd64.tar.gz -o /tmp/k9s_Linux_amd64.tar.gz
echo "b0eb5fb0decedbee5b6bd415f72af8ce6135ffb8128f9709bc7adcd5cbfa690b  k9s_Linux_amd64.tar.gz" > /tmp/k9s.sha256
sha256sum -c /tmp/k9s.sha256
tar -zxvf /tmp/k9s_Linux_amd64.tar.gz  -C /tmp
mv /tmp/k9s /usr/local/bin/
cd /root

# Install Ingress Nginx
mkdir -p /var/lib/rancher/k3s/server/manifests/
cat << YAML >> /var/lib/rancher/k3s/server/manifests/ingress-nginx.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: ingress-nginx
---
apiVersion: helm.cattle.io/v1
kind: HelmChart
metadata:
  name: ingress-nginx
  namespace: kube-system
spec:
  repo: https://kubernetes.github.io/ingress-nginx
  chart: ingress-nginx
  version: 4.4.2
  targetNamespace: ingress-nginx
---
apiVersion: helm.cattle.io/v1
kind: HelmChartConfig
metadata:
  name: ingress-nginx
  namespace: kube-system
spec:
  valuesContent: |-
    controller:
      watchIngressWithoutClass: true
YAML

cat << YAML >> /var/lib/rancher/k3s/server/manifests/studio.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: studio
YAML

# Install Helm - script uploaded with packer
bash /home/ubuntu/.studio_install/helm3.sh

# Add Helm Iterative Repository
helm repo add iterative https://helm.iterative.ai

# Copy the support bundle script
cp /home/ubuntu/.studio_install/create-support-bundle /usr/local/bin/create-support-bundle
chmod +x /usr/local/bin/create-support-bundle
