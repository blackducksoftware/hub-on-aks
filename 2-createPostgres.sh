#!/bin/bash
. vars.env
. verify.sh


#Create new postgres passwords if they're not already defined.
export LC_CTYPE=C
if [ ! -f "${PG_ADMIN_PW_FILE}" ]; then
    echo Writing new postgres admin password to ${PG_ADMIN_PW_FILE}
    cat /dev/urandom | tr -dc '_A-Z-a-z-0-9\(\)=+!@#\$%&*' | head -c 16 > ${PG_ADMIN_PW_FILE}
else
    echo Using postgres admin password from ${PG_ADMIN_PW_FILE}
fi

if [ ! -f "${PG_USER_PW_FILE}" ]; then
    echo Writing new postgres user password to ${PG_USER_PW_FILE}
    cat /dev/urandom | tr -dc '_A-Z-a-z-0-9\(\)=+!@#\$%&*' | head -c 16 > ${PG_USER_PW_FILE}
else
    echo Using postgres user password from ${PG_USER_PW_FILE}
fi

export PGPASSWORD=$(cat ${PG_ADMIN_PW_FILE})

#Create instance
az postgres server create --resource-group "${RESOURCE_GROUP_NAME}" --name "${DB_INSTANCE_NAME}"  --location ${ZONE} --admin-user "${PG_ADMIN_USER}" --admin-password "${PGPASSWORD}" --sku-name "GP_Gen5_4" --version "9.6" --ssl-enforcement "Disabled" --storage-size "$((1024*$MAX_DB_SIZE_GB))"
DB_SERVER_ADDRESS=$(az postgres server show --resource-group $RESOURCE_GROUP_NAME  --name $DB_INSTANCE_NAME --query fullyQualifiedDomainName --output tsv)

if [ -z "${DB_SERVER_ADDRESS}" ]; then
    echo DB server not created successfully
    exit 1
fi

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

# Allow access from Azure IPs
az postgres server firewall-rule create --resource-group ${RESOURCE_GROUP_NAME} --server ${DB_INSTANCE_NAME} --name azureIpAccess --start-ip-address 0.0.0.0 --end-ip-address 0.0.0.0

