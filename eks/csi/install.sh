#!/bin/bash

# aws-ebs-csi-driver is installed automatically via cluster.yaml addons.
# If it failed during cluster creation (no network yet), install manually:
#   eksctl create addon --name aws-ebs-csi-driver --cluster my-cluster --region us-east-1 --force

# Check PVC status after apply:
#   kubectl get pvc
#   kubectl get pv

# View created EBS volumes in AWS:
#   aws ec2 describe-volumes --region us-east-1 \
#     --filters "Name=tag-key,Values=kubernetes.io/created-for/pvc/name" \
#     --query 'Volumes[*].{ID:VolumeId,Size:Size,AZ:AvailabilityZone,State:State,PVC:Tags[?Key==`kubernetes.io/created-for/pvc/name`].Value|[0]}' \
#     --output table

kubectl apply -f storageclass.yaml
kubectl apply -f pvc.yaml
kubectl apply -f pod.yaml
