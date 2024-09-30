#!/bin/bash

set -eu

eval $(azd env get-values)

: ${RM_REPOSITORY=https://github.com/yaegashi/dx2devops-rm-docker}
: ${RM_REF=main}
: ${REDMINE_REPOSITORY=https://github.com/redmica/redmica}
: ${REDMINE_REF=v3.0.3}

if ! test -d rm; then
    git clone $RM_REPOSITORY -b $RM_REF rm
fi

if ! test -d rm/redmine; then
    git clone $REDMINE_REPOSITORY -b $REDMINE_REF rm/redmine
fi

CONTAINER_REGISTRY_NAME=$(az group show --subscription ${AZURE_SUBSCRIPTION_ID} -g ${SHARED_RESOURCE_GROUP_NAME} --query tags.CONTAINER_REGISTRY_NAME -o tsv)
CONTAINER_REGISTRY_ENDPOINT=$(az group show --subscription ${AZURE_SUBSCRIPTION_ID} -g ${SHARED_RESOURCE_GROUP_NAME} --query tags.CONTAINER_REGISTRY_ENDPOINT -o tsv)

IMAGE=${CONTAINER_REGISTRY_ENDPOINT}/${AZURE_ENV_NAME}
TAG=$(date --utc +%Y%m%dT%H%M%SZ)

docker build rm -t ${IMAGE}:${TAG}

az acr login --subscription ${AZURE_SUBSCRIPTION_ID} --name ${CONTAINER_REGISTRY_NAME}

docker push ${IMAGE}:${TAG}

azd env set APP_IMAGE ${IMAGE}:${TAG}
