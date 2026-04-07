#!/bin/bash

# Install AWS CLI
if ! command -v aws &>/dev/null; then
  curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o awscliv2.zip
  unzip awscliv2.zip && sudo ./aws/install
fi

# Configure AWS credentials
aws configure

# Install eksctl
if ! command -v eksctl &>/dev/null; then
  ARCH=amd64
  PLATFORM=$(uname -s)_$ARCH
  curl -sLO "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_$PLATFORM.tar.gz"
  tar -xzf eksctl_$PLATFORM.tar.gz -C /tmp
  sudo mv /tmp/eksctl /usr/local/bin
fi

# Install kubectl
if ! command -v kubectl &>/dev/null; then
  curl -LO "https://dl.k8s.io/release/$(curl -Ls https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
  chmod +x kubectl && sudo mv kubectl /usr/local/bin
fi

# Install helm
if ! command -v helm &>/dev/null; then
  curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
fi

# Create EKS cluster (no kube-proxy, OIDC enabled for IRSA)
# NOTE: if previous cluster deletion failed with DELETE_FAILED on subnets,
# find and delete orphaned Cilium ENIs manually before creating:
#   aws ec2 describe-network-interfaces --filters "Name=description,Values=Cilium*" \
#     --query 'NetworkInterfaces[*].NetworkInterfaceId' --output text
#   aws ec2 delete-network-interface --network-interface-id <id>
# Then retry: aws cloudformation delete-stack --stack-name eksctl-<name>-cluster
eksctl create cluster -f cluster.yaml

# Update kubeconfig
# NOTE: cluster name must match metadata.name in cluster.yaml
aws eks update-kubeconfig --name my-cluster --region us-east-1

# Disable aws-node (VPC CNI) - Cilium replaces it completely.
# We use a nodeSelector that no node has, so the daemonset runs on 0 nodes.
# Do NOT delete aws-node - EKS managed addon will try to recreate it.
kubectl -n kube-system patch daemonset aws-node --type=json \
  -p='[{"op":"replace","path":"/spec/template/spec/nodeSelector","value":{"io.cilium/aws-node-enabled":"true"}}]'

# Delete kube-proxy - Cilium replaces it via eBPF (kubeProxyReplacement=true).
# If delete fails on re-run it's fine, hence --ignore-not-found.
kubectl -n kube-system delete daemonset kube-proxy --ignore-not-found

# Install Cilium in overlay (VXLAN) mode with kube-proxy replacement.
# VXLAN instead of ENI native routing - ENI native has a known bug where pods
# on secondary ENIs lose internet access (egress silently dropped).
# VXLAN uses node IP for SNAT so all pods reliably reach the internet.
API_SERVER=$(kubectl config view --raw --minify --flatten -o jsonpath='{.clusters[0].cluster.server}' | sed 's|https://||')

helm repo add cilium https://helm.cilium.io && helm repo update

helm install cilium cilium/cilium --namespace kube-system \
  --set routingMode=tunnel \
  --set tunnelProtocol=vxlan \
  --set kubeProxyReplacement=true \
  --set k8sServiceHost=${API_SERVER} \
  --set k8sServicePort=443 \
  --set bpf.masquerade=true \
  --set hubble.relay.enabled=true \
  --set hubble.ui.enabled=true

# Remove taint that was blocking pod scheduling until Cilium is ready
kubectl taint nodes --all node.cilium.io/agent-not-ready-

# Re-create addons that may have failed during cluster creation (no network at that point).
# aws-ebs-csi-driver needs IAM role - eksctl creates it automatically with --force:
#   eksctl create addon --name aws-ebs-csi-driver --cluster my-cluster --region us-east-1 --force
# metrics-server usually recovers on its own after Cilium is up.

kubectl -n kube-system patch svc hubble-ui -p '{"spec":{"type":"LoadBalancer"}}'
kubectl create clusterrolebinding hubble-ui-admin --clusterrole=cluster-admin --serviceaccount=kube-system:hubble-ui
