#!/bin/bash

BASEDIR=$(dirname "$0")
cd $BASEDIR
. verify.sh
az login && ./1-create.sh && ./2-createPostgres.sh && ./3-createStorage.sh && sleep 5 && ./4-deployApplication.sh
