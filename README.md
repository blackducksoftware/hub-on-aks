# Installing Hub on Azure Kubernetes Service (AKS)

## Requirements
* Azure subscription
* Azure user account with role "Owner" in the Azure subscription
* Docker, or:
  * Bash shell
  * [Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli?view=azure-cli-latest)
  * `psql` - Postgres client utility.

Provided in this repository are all the files needed to provision all the requisite Azure resources and install Hub with minimal effort. Follow the "Automated cluster creation" section to create a new resource group, a new Kuberenetes cluster, a new instance of Azure Database for Postgres, and install Hub.

If you prefer to step through the installation manually, making changes along the way, follow the "Manual cluster creation" section.

## Selecting the region

You will need to select an [Azure Region](https://azure.microsoft.com/en-us/global-infrastructure/locations/) for your installation. This region needs to offer Azure Kubernetes Service (AKS) and Azure Database for PostgreSQL. Use [this page](https://azure.microsoft.com/en-us/global-infrastructure/services/) to see available services by region.

## Automated cluster creation

Note: Your cluster will be created using the SSH key pair in your `~/.ssh` directory. If no key pair is present, one will be generated. To use a different key pair, edit the script `1-create.sh` or follow the "Manual Cluster Creation" steps.

1. (Optional) Edit the file `vars.env` in this repository. If needed, set the ZONE field chosen in the previous section. You can modify other fields, subject to [Azure constraints](https://docs.microsoft.com/en-us/azure/architecture/best-practices/naming-conventions).

2. If you have Azure CLI and `psql` installed on your local system, you can setup the cluster by running `full-install.sh`.

If you lack those prerequisites, you can build an image containing them from the included docker file, and run the install from a container running that image:

```bash
docker build . -f ./install_dockerfile -t blackducksoftware/hub-aks-install:latest
docker run -it --mount type=bind,source="$(pwd)",target=/install --mount type=bind,source=${HOME}/.ssh,target=/root/.ssh  blackducksoftware/hub-aks-install /install/full-install.sh
```

Once the final script has been run, you can use the command `kubectl --namespace $CLUSTER_NAME get service webserver-gateway` to view the external IP address of the new Hub instance.

*Note:* even after the completion of the final script, it make take several minutes for the Hub application to first become available.



## Manual custer creation

### 1. Creating the Cluster

Create a resource group that will contain both the cluster and the Azure DB for Postgres instance.

```bash
az group create --name $RESOURCE_GROUP_NAME --location $ZONE
```

Next, we'll need to create a service principal to own the cluster. Because the service principal will need a strong password, we recommmend generating one.

```bash
GROUP_ID=$(az group show -g $RESOURCE_GROUP_NAME --query id --output tsv)
SERVICE_PRINCIPAL_PASSWORD=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9\!\#\^' | fold -w 32 | head -n 1)
SP_APP_ID=$(az ad sp create-for-rbac --name ${CLUSTER_NAME} --password "${SERVICE_PRINCIPAL_PASSWORD}" --role="Contributor" --scopes="$GROUP_ID" --query appId --output tsv)
```

Now, we're ready to provision the cluster itself:
```bash
az aks create --name "$CLUSTER_NAME" --resource-group "$RESOURCE_GROUP_NAME" \
    --kubernetes-version "$KUBERNETES_VERSION"\
    --node-osdisk-size "30"\
    --node-count ${NODE_COUNT} \
    --node-vm-size "${VM_SIZE}" \
    --service-principal $SP_APP_ID --client-secret "${SERVICE_PRINCIPAL_PASSWORD}"
```

We recommend using Kubernetes version 1.9.6 with at least five nodes, with VM size `Standard_D4_v3` or higher. If you don't have an SSH key pair in your `~/.ssh` directory, add the `--generate-ssh-keys` parameter to the `az create` command to generate a new key pair. If you wish to use a different key pair, add the `--ssh-key-value` followed by the path to or the value of the desired SSH public key.

#### Installing and configuring `kubectl`

You will need the `kubectl` utility to configure and deploy the application. If you do not have it installed, the Azure CLI can install it for you:

```bash
az aks install-cli
```

Once you have the `kubectl` tool, set up your access to the AKS cluster:

```bash
az aks get-credentials --resource-group $RESOURCE_GROUP_NAME --name ${CLUSTER_NAME}
```

The cluster is now ready for configuration deployment.

### 2. Configuring the Database

Hub uses Postgres as its backing database. While this database can be just another node in your cluster, we highly recommend using [Azure DB for PostgreSQL](https://azure.microsoft.com/en-us/services/postgresql/) as Hub's data store. AzureDB for Postgres provides added security and reliability features (such as automatic backups) without any additional effort on your part.

To work with Azure DB for PostgreSQL from the command line, you'll first need to install the RDBMS extension for Azure CLI:

```bash
az extension add --name rdbms
```

Because the database will be accessible from all Azure IP addresses, it is imperative that all database users have strong passwords. You can use this snippet to generate these passwords after setting the variables `PG_ADMIN_PW_FILE` and `PG_USER_PW_FILE` to paths of files that will contain your passwords.

```bash
export LC_CTYPE=C
cat /dev/urandom | tr -dc '_A-Z-a-z-0-9\(\)=+!@#\$%&*' | head -c 16 > ${PG_ADMIN_PW_FILE}
cat /dev/urandom | tr -dc '_A-Z-a-z-0-9\(\)=+!@#\$%&*' | head -c 16 > ${PG_USER_PW_FILE}
```

With the strong passwords created, proceed to create the database:
```bash
az postgres server create --resource-group "${RESOURCE_GROUP_NAME}" --name "${DB_INSTANCE_NAME}"  --location ${ZONE} --admin-user "${PG_ADMIN_USER}" --admin-password "$(cat ${PG_ADMIN_PW_FILE})" --sku-name "GP_Gen4_2" --version "9.6" --ssl-enforcement "Disabled"
```

The `--location` value should match that of the kubernetes cluster. You may wish to add the `--backup-retention` parameter to set how long database backups should be retained. You may also wish to add the `--geo-redundant-backup` parameter to make database backups geo-redundant. See [Azure documentation on your backup and restore options](https://docs.microsoft.com/en-us/azure/postgresql/concepts-backup). 

Once the database is created, you will need to run the initialization script. To do this, you'll need to create a firewall rule to allow access from your computer, run the initialization script, then delete the firewall rule:

```bash
# Allow access from our local IP
MY_IP="$(dig TXT +short o-o.myaddr.l.google.com @ns1.google.com | awk -F'"' '{ print $2}')"
    #Enable access from our server
az postgres server firewall-rule create --resource-group ${RESOURCE_GROUP_NAME} --server ${DB_INSTANCE_NAME} --name allowLocalMods --start-ip-address ${MY_IP} --end-ip-address ${MY_IP}
#Now that we have access, run the database initialization script
cat sql/external-postgres-init.pgsql | psql --host=${DB_SERVER_ADDRESS} --port 5432 --user="${PG_ADMIN_USER}@${DB_INSTANCE_NAME}" --dbname=postgres
#Set user passwords
echo "ALTER ROLE blackduck_user WITH PASSWORD '$(cat ${PG_USER_PW_FILE})';" | psql --host=${DB_SERVER_ADDRESS} --port 5432 --user="${PG_ADMIN_USER}@${DB_INSTANCE_NAME}" --dbname=postgres
echo "ALTER ROLE blackduck_reporter WITH PASSWORD 'blackduck';" | psql --host=${DB_SERVER_ADDRESS} --port 5432 --user="${PG_ADMIN_USER}@${DB_INSTANCE_NAME}" --dbname=postgres
# Remove access from our local IP
az postgres server firewall-rule delete --resource-group ${RESOURCE_GROUP_NAME} --server ${DB_INSTANCE_NAME} --name allowLocalMods --yes
```

Note: the above step requires the `psql` utility. If you do not have it locally available and do not wish to install it, run the `postgres` docker image and use the tool there.

Finally, you will need to allow access from other Azure IPs, so that the database will be accessible from the Kubernetes cluster:

```bash
az postgres server firewall-rule create --resource-group ${RESOURCE_GROUP_NAME} --server ${DB_INSTANCE_NAME} --name azureIpAccess --start-ip-address 0.0.0.0 --end-ip-address 0.0.0.0
```

### 3. Persistent Storage.
Some of the Hub containers require the use of Persistent Volumes in order to scale or restart without requiring additonal manual intervention.

To set up storage on Azure, you will first need to create or provide a storage account in the same region as the Kubernetes cluster. The simplest method is to use dynamic storage in a storage account created specifically inside the cluster's internal resource group.

*Note:* Azure imposes a limit of 200 storage accounts per region per subscription. If this limit makes creating a new storage account for the Hub cluster impossible, consult [Azure Files - Static](https://docs.microsoft.com/en-us/azure/aks/azure-files-volume) documentation and the Hub installation guide to configure static Azure File persistent volumes. Do not follow the remainder of this section.

To create storage account for the cluster:
```bash
#Get the name of the resource group Azure has created internally for this cluster
KUBE_CLUSTER_RESOURCE_GROUP=$(az resource show --resource-group ${RESOURCE_GROUP_NAME} --name ${CLUSTER_NAME} --resource-type Microsoft.ContainerService/managedClusters --query properties.nodeResourceGroup -o tsv)

#Create a globally unique storage account inside cluster's internal resource group
STORAGE_ACCOUNT_NAME=$( cat /dev/urandom | tr -dc 'a-z0-9' | head -c 24)
az storage account create --resource-group $KUBE_CLUSTER_RESOURCE_GROUP --name ${STORAGE_ACCOUNT_NAME} --location $ZONE --sku Standard_LRS
```

Next, create a [storage class](https://kubernetes.io/docs/concepts/storage/storage-classes/) for Azure File using the following template:
```yaml
kind: StorageClass
apiVersion: storage.k8s.io/v1
metadata:
  name: azurefile
provisioner: kubernetes.io/azure-file
parameters:
  storageAccount: ${STORAGE_ACCOUNT}
mountOptions:
  - dir_mode=0777
  - file_mode=0777
```

```bash
sed 's/${STORAGE_ACCOUNT}/'$STORAGE_ACCOUNT_NAME'/g' yml/storage-class-template.yml | kubectl --namespace=${CLUSTER_NAME} apply -f -
```

Finally, we need to create Persistent Volume Claims of the class defined in the previous step. For each volume in the Hub-YAML files, create a Persistent Volume Claim with the following template:
```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ${NAME}
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: azurefile
  resources:
    requests:
      storage: 1Gi
```

You do not need to create persistent volumes for these claims. AKS will do that automatically.

### 4. Deploying the Hub Application
All the necessary components for running Hub in Kubernetes have now been created. The last step is to adapt the Hub orchestration for running on AKS.

First, create the `db-creds` secret with the database passwords created in section 2.
```bash
PG_ADMIN_PW=$(cat ${PG_ADMIN_PW_FILE})
PG_USER_PW=$(cat ${PG_USER_PW_FILE})
kubectl create secret generic db-creds --from-literal="blackduck=${PG_ADMIN_PW}" --from-literal="blackduck_user=${PG_USER_PW}" --namespace "${CLUSTER_NAME}"
```

Next, create the ConfigMap named hub-db-config. Azure Database for PostgreSQL requires that all connections must provide the username in the form `${DB_USER_NAME}@${DB_INSTANCE_NAME}`. Use the following template to create the ConfigMap:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: hub-db-config
data:
  HUB_POSTGRES_ENABLE_SSL: "false"
  HUB_POSTGRES_USER: "${PG_USER}@${DB_INSTANCE_NAME}"
  HUB_POSTGRES_ADMIN: "${PG_ADMIN_USER}@${DB_INSTANCE_NAME}"
  HUB_POSTGRES_HOST: "${DB_SERVER_ADDRESS}"
```

Lastly, modify each of the Hub YAML files to use the Persistent Volume Claims created in step 3. After making these modifications, you can deploy the YAML files:

```bash
kubectl create -f yml/1-cm-hub.yml --namespace "${CLUSTER_NAME}" 
kubectl create -f yml/1-cfssl.yml --namespace "${CLUSTER_NAME}" 
```

Wait until the `cfssl` pod has started (using `kubectl --namespace ${CLUSTER_NAME} get pods`). Then proceed to deploy the remaining containers:

```
kubectl create -f yml/2-postgres-db-external.yml --namespace "${CLUSTER_NAME}" 
kubectl create -f yml/3-hub.yml --namespace "${CLUSTER_NAME}" 
```

Finally, expose the `nginx-webapp-logstash` service on an external IP address:
```bash
kubectl --namespace=$CLUSTER_NAME expose service webserver --type=LoadBalancer --port=443 --target-port=8443 --name=webserver-gateway
```
### Working with the cluster after installation.

To obtain command-line access to your cluster, use the command:
```bash
az aks get-credentials --resource-group $RESOURCE_GROUP_NAME --name ${CLUSTER_NAME}
```

You can then view the resulting externally-accessible IP address via 
```bash
kubectl --namespace $CLUSTER_NAME get service webserver-gateway
```

#### Cleaning up the Postgres container
The Hub orchestration creates a Postgres contaner, for use when the database is hosted inside the Kubernetes cluster. Since your deployment uses Azure Database for PostgreSQL, you can delete the Postgres container:

```bash
kubectl --namespace $CLUSTER_NAME delete replicationController -l app=postgres
```
