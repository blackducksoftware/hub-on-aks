#!/bin/bash
. vars.env

#Delete the cluster
az aks delete --resource-group $RESOURCE_GROUP_NAME --name $CLUSTER_NAME --yes --no-wait

#Remove the owning resource group
az group delete --yes --resource-group $RESOURCE_GROUP_NAME --no-wait

#Remove the Active Directory application(s) created.
APPS=$(az ad app list --display-name $CLUSTER_NAME --query [].appId  --output tsv)
for app in $APPS; do
    az ad app delete --id $app
done
#The above should remove the service principal itself
