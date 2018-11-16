#!/usr/bin/env bash
set -e

for var in AZURE_SUBSCRIPTION_ID AZURE_TENANT_ID AZURE_CLIENT_ID AZURE_CLIENT_SECRET nutoken vnetid loadBalancerFrontEndTarget resourceGroup location
do
	if [ -z "${!var}" ]
	then
		echo "$var environment variable not set"
		exit 1
	fi
done

baseurl="https://i.nuos.io/${scriptdir}api/1.1/wf/"

sudo apt-get install -y docker.io

sudo docker ps | grep -q elephant || sudo docker run -p80:80 -v /:/host -v /var/run/docker.sock:/var/run/docker.sock --privileged --name elephant -d --restart=on-failure --net=host nubeva/nuagent:eleph --accept-eula --nutoken $nutoken  --vxlan-port 4789 --vnet $vnetid --baseurl $baseurl  --ruok-port 80

sudo docker inspect vagent > /dev/null 2>&1 || sudo docker run --name vagent -d -e AZURE_SUBSCRIPTION_ID=$AZURE_SUBSCRIPTION_ID -e AZURE_TENANT_ID=$AZURE_TENANT_ID -e AZURE_CLIENT_ID=$AZURE_CLIENT_ID -e AZURE_CLIENT_SECRET=$AZURE_CLIENT_SECRET nubeva/vagent:eleph --vnet $vnetid  --target $loadBalancerFrontEndTarget --nutoken $nutoken --baseurl $baseurl --resource-group $resourceGroup --location $location

