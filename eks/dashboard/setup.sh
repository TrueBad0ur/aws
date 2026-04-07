#!/bin/bash

kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.7.0/aio/deploy/recommended.yaml

kubectl -n kubernetes-dashboard patch svc kubernetes-dashboard --type=json -p='[{"op":"replace","path":"/spec/ports","value":[{"name":"https","port":443,"targetPort":8443,"protocol":"TCP"}]},{"op":"replace","path":"/spec/type","value":"LoadBalancer"}]'

kubectl patch deployment kubernetes-dashboard -n kubernetes-dashboard --type=json -p='[{"op":"replace","path":"/spec/template/spec/containers/0/livenessProbe","value":{"httpGet":{"path":"/","port":8443,"scheme":"HTTPS"},"initialDelaySeconds":30,"timeoutSeconds":30,"periodSeconds":10,"failureThreshold":3}}]'

kubectl create clusterrolebinding kubernetes-dashboard-admin --clusterrole=cluster-admin --serviceaccount=kubernetes-dashboard:kubernetes-dashboard

echo "Token:"
kubectl -n kubernetes-dashboard create token kubernetes-dashboard --duration=24h
