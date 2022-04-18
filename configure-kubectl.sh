#!/usr/bin/env bash


declare CLUSTER_ID
declare main_controller_address

kubectl config set-cluster "$CLUSTER_ID" \
  --certificate-authority=certs/ca.pem \
  --embed-certs=true \
  --server="https://$main_controller_address:6443"

kubectl config set-credentials admin \
  --client-certificate=certs/admin.pem \
  --client-key=certs/admin-key.pem \

kubectl config set-context "$CLUSTER_ID" \
  --cluster="$CLUSTER_ID" \
  --user=admin

kubectl config use-context "$CLUSTER_ID"
