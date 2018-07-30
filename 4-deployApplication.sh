#!/bin/bash
. vars.env
. verify.sh


DB_SERVER_ADDRESS=$(az postgres server show --resource-group $RESOURCE_GROUP_NAME  --name $DB_INSTANCE_NAME --query fullyQualifiedDomainName --output tsv)


#Create Postgres secrets
PG_ADMIN_PW=$(cat ${PG_ADMIN_PW_FILE})
PG_USER_PW=$(cat ${PG_USER_PW_FILE})
kubectl create secret generic db-creds --from-literal="blackduck=${PG_ADMIN_PW}" --from-literal="blackduck_user=${PG_USER_PW}" --namespace "${CLUSTER_NAME}"

# Create the hub-db-config configmap
echo Deploying to cluster...
sed 's/${DB_SERVER_ADDRESS}/'$DB_SERVER_ADDRESS'/g' yml/hub-db-config.env | sed 's/${PG_ADMIN_USER}/'${PG_ADMIN_USER}'/g' | sed 's/${PG_USER}/'${PG_USER}'/g'  | sed 's/${DB_INSTANCE_NAME}/'$DB_INSTANCE_NAME'/g' | kubectl --namespace=${CLUSTER_NAME} create -f -

kubectl create -f yml/1-cm-hub.yml --namespace "${CLUSTER_NAME}" 
kubectl create -f yml/1-cfssl.yml --namespace "${CLUSTER_NAME}"

until [ "$(kubectl --namespace $CLUSTER_NAME get pods -l app=cfssl -o jsonpath='{$.items.*.status.containerStatuses.*.ready}')" == "true" ]; do
    echo 'Waiting for cfssl pod to start...'
    sleep 2
done

kubectl create -f yml/2-postgres-db-external.yml --namespace "${CLUSTER_NAME}" 
kubectl create -f yml/3-hub.yml --namespace "${CLUSTER_NAME}" 
echo Cluster created. Exposing...

kubectl --namespace=$CLUSTER_NAME expose service webserver --type=LoadBalancer --port=443 --target-port=8443 --name=webserver-gateway

# The postgres pod is superfluous, since we're using AzureDB for Postgres. Whack that pod.
kubectl --namespace $CLUSTER_NAME delete replicationController -l app=postgres


