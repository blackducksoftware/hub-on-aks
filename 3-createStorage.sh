#!/bin/bash
. vars.env
. verify.sh

KUBE_CLUSTER_RESOURCE_GROUP=$(az resource show --resource-group ${RESOURCE_GROUP_NAME} --name ${CLUSTER_NAME} --resource-type Microsoft.ContainerService/managedClusters --query properties.nodeResourceGroup -o tsv)

#Create a globally unique storage account inside cluster's internal resource group
STORAGE_ACCOUNT_NAME=$( cat /dev/urandom | tr -dc 'a-z0-9' | head -c 24)
az storage account create --resource-group $KUBE_CLUSTER_RESOURCE_GROUP --name ${STORAGE_ACCOUNT_NAME} --location $ZONE --sku Standard_LRS

# Give azure's storage creator service user the permission to PVCs in the cluster
kubectl --namespace="${CLUSTER_NAME}" create clusterrole system:azure-cloud-provider --verb=get,create --resource=secrets
kubectl --namespace="${CLUSTER_NAME}" create clusterrolebinding system:azure-cloud-provider --clusterrole=system:azure-cloud-provider --serviceaccount=kube-system:persistent-volume-binder

# Create Azure File storage class
sed 's/${STORAGE_ACCOUNT}/'$STORAGE_ACCOUNT_NAME'/g' yml/storage-class-template.yml | kubectl --namespace=${CLUSTER_NAME} apply -f -

# Create Persistent Volume Claims.
kubectl --namespace="${CLUSTER_NAME}" apply -f yml/persistent-volume-claims.yml
