#!/bin/bash

# Install flux CLI
curl -s https://fluxcd.io/install.sh | sudo bash

# Bootstrap Flux into cluster - creates GitHub repo, adds deploy key,
# pushes Flux manifests to clusters/my-cluster/ and deploys controllers.
# Requires GITHUB_TOKEN with 'repo' scope.
export GITHUB_TOKEN=<token>
flux bootstrap github \
  --owner=<github-username> \
  --repository=<repo-name> \
  --branch=main \
  --path=clusters/my-cluster \
  --personal

# Clone the repo that flux bootstrap created/configured
git clone https://github.com/<github-username>/<repo-name>

# Install Weave GitOps UI (Flux UI)
# bcrypt hash generation: htpasswd -nbBC 10 "" "yourpassword" | tr -d ':\n'
HASH=$(htpasswd -nbBC 10 "" "password" | tr -d ':\n')
helm install weave-gitops oci://ghcr.io/weaveworks/charts/weave-gitops \
  --version 4.0.36 \
  -n flux-system \
  --set adminUser.create=true \
  --set adminUser.username=admin \
  --set "adminUser.passwordHash=${HASH}" \
  --set service.type=LoadBalancer

# Get Weave GitOps URL
kubectl get svc weave-gitops -n flux-system
# Access: http://<EXTERNAL-IP>:9001
# Login: admin / password
