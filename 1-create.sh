#!/bin/bash
. vars.env
. verify.sh

#Create resource group
az group create --name $RESOURCE_GROUP_NAME --location $ZONE
echo Resource group \"$RESOURCE_GROUP_NAME\" created

#Create a service principal
echo "Creating the service principal..."
GROUP_ID=$(az group show -g $RESOURCE_GROUP_NAME --query id --output tsv)
SERVICE_PRINCIPAL_PASSWORD=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9\!\#\^' | fold -w 32 | head -n 1)
SP_APP_ID=$(az ad sp create-for-rbac --name ${CLUSTER_NAME} --password "${SERVICE_PRINCIPAL_PASSWORD}" --role="Contributor" --scopes="$GROUP_ID" --query appId --output tsv)
echo Service principal created. App ID: $SP_APP_ID

#Wait for Azure to catch its breath
sleep 5
#Create the cluster
echo "Creating the cluster...";
az aks create --name "$CLUSTER_NAME" --resource-group "$RESOURCE_GROUP_NAME" \
    --kubernetes-version "$KUBERNETES_VERSION"\
    --node-osdisk-size "30"\
    --node-count ${NODE_COUNT} \
    --node-vm-size "${VM_SIZE}" \
    --service-principal $SP_APP_ID --client-secret "${SERVICE_PRINCIPAL_PASSWORD}" --generate-ssh-keys

#Exit if cluster not created
CLUSTER_ID=$(az aks list --resource-group $RESOURCE_GROUP_NAME --query [].name --output tsv)
if [ -z "$CLUSTER_ID" ]; then
    echo "Cluster has not been created successfully. Exiting." 1>&2
    exit 1
fi


# Obtain credentials and create namespace (for subsequent steps)
az aks get-credentials --resource-group $RESOURCE_GROUP_NAME --name ${CLUSTER_NAME}
kubectl create namespace "${CLUSTER_NAME}"

echo Cluster created. Time to deploy...

