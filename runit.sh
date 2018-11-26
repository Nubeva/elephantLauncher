#!/usr/bin/env bash
set -e

export TAG="elephant"

for var in AZURE_STORAGE_ACCOUNT AZURE_SUBSCRIPTION_ID AZURE_TENANT_ID AZURE_CLIENT_ID AZURE_CLIENT_SECRET nutoken vnetid loadBalancerFrontEndTarget resourceGroup location pspid
do
	if [ -z "${!var}" ]
	then
		echo "$var environment variable not set"
		exit 1
	fi
done

baseurl="https://i.nuos.io/${scriptdir}api/1.1/wf/"

sudo apt-get install -y docker.io

# data path
if [ "$1" != "CONTROLONLY" ]; then
sudo docker pull nubeva/elephant:$TAG | grep "newer image" && ( sudo docker rm -vf elephant || true )
sudo docker ps --format '{{.Names}}' | grep -v elephant-control | grep -q '^elephant' || sudo docker run -e AZURE_SUBSCRIPTION_ID=$AZURE_SUBSCRIPTION_ID -e AZURE_TENANT_ID=$AZURE_TENANT_ID -e AZURE_CLIENT_ID=$AZURE_CLIENT_ID -e AZURE_CLIENT_SECRET=$AZURE_CLIENT_SECRET -e AZURE_RESOURCE_GROUP=$resourceGroup -e AZURE_LOCATION=$location -e AZURE_STORAGE_ACCOUNT=$AZURE_STORAGE_ACCOUNT -v /:/host -v /var/run/docker.sock:/var/run/docker.sock --name elephant -d --restart=always --net=host nubeva/elephant:$TAG --accept-eula --ruok-port 80 --vxlan-port 4789 --psp-id $pspid
fi

# control path
if [ "$1" != "DATAONLY" ]; then
sudo docker pull nubeva/elephant-control:$TAG | grep "newer image" && ( sudo docker rm -vf elephant-control || true )
sudo docker ps --format '{{.Names}}' | grep -q '^elephant-control' || sudo docker run -e AZURE_SUBSCRIPTION_ID=$AZURE_SUBSCRIPTION_ID -e AZURE_TENANT_ID=$AZURE_TENANT_ID -e AZURE_CLIENT_ID=$AZURE_CLIENT_ID -e AZURE_CLIENT_SECRET=$AZURE_CLIENT_SECRET -e AZURE_RESOURCE_GROUP=$resourceGroup -e AZURE_LOCATION=$location -e AZURE_STORAGE_ACCOUNT=$AZURE_STORAGE_ACCOUNT -v /:/host -v /var/run/docker.sock:/var/run/docker.sock --name elephant-control -d --restart=always --net=host nubeva/elephant-control:$TAG --accept-eula --nutoken $nutoken --baseurl $baseurl --psp-id $pspid
fi
# sudo docker inspect vagent > /dev/null 2>&1 || sudo docker run --name vagent -d -e AZURE_SUBSCRIPTION_ID=$AZURE_SUBSCRIPTION_ID -e AZURE_TENANT_ID=$AZURE_TENANT_ID -e AZURE_CLIENT_ID=$AZURE_CLIENT_ID -e AZURE_CLIENT_SECRET=$AZURE_CLIENT_SECRET nubeva/elephant-control:elephant  --target $loadBalancerFrontEndTarget --nutoken $nutoken --baseurl $baseurl --resource-group $resourceGroup --location $location
