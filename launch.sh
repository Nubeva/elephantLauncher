#!/usr/bin/env bash
set -e

echo "Validating parameters..."
# Required vars
for var in nutoken resourcegroup vnetname
do
	if [ -z "${!var}" ]
	then
		echo "$var environment variable not set"
		exit 1
	fi
done

# Validation
if [ "$(az group exists --name ${resourcegroup})" != "true" ]
then
	echo "Unable to find resource group named '${resourcegroup}'"
	exit 1
fi

if ! az network vnet show -g ${resourcegroup} -n ${vnetname} > /dev/null
then
	echo "Unable to find vnet '${vnetname}' in resource group '${resourcegroup}'"
	exit 1
fi

# use the first subnet in the vnet
subnetName=$(az network vnet subnet list -g "${resourcegroup}" --vnet-name ${vnetname} --query '[0].name' --output tsv)
if [ -z "$subnetName" ]
then
	echo "Unable to find a subnet to use in vnet '${vnetname}' in resource group '${resourcegroup}'"
	exit 1
fi

#Optional vars
if [ -z "$ROLENAME"]
then
    ROLENAME="NubevaVTap"
fi

if [ -z "$SUBSCRIPTION_ID" ]
then
  SUBSCRIPTION_ID=$(az account show --query id  --output tsv)
fi

if [ -z "$TEMPLATE_BRANCH" ]
then
	TEMPLATE_BRANCH="master"
fi

if [ -z "$TEMPLATE_URI"]
then
	TEMPLATE_URI="https://raw.githubusercontent.com/Nubeva/elephantLauncher/${TEMPLATE_BRANCH}/elephant_launch.json"
fi

######################
# Minimal permissions
######################
# All access on Taps:                             "Microsoft.Network/virtualNetworkTaps/*",
# All access on TapConfigs:                       "Microsoft.Network/networkInterfaces/tapConfigurations/*",
# Read perms to list network interfaces:          "Microsoft.Network/networkInterfaces/read",
# Ability to connect a tap to the load balancer:  "Microsoft.Network/loadBalancers/frontendIPConfigurations/join/action",
# Ability to read meta data about an instance     "Microsoft.Compute/virtualMachines/read"
######################


elephantRole='{
    "Name":  "NubevaVTap",
    "IsCustom":  true,
    "Description":  "Role with minimum requirements for the Nubeva Elephant to operate",
    "Actions":  [
        "Microsoft.Network/virtualNetworkTaps/*",
        "Microsoft.Network/networkInterfaces/tapConfigurations/*",
        "Microsoft.Network/networkInterfaces/read",
        "Microsoft.Network/loadBalancers/frontendIPConfigurations/join/action",
        "Microsoft.Compute/virtualMachines/read"
                ],
    "NotActions":  [

                   ],
    "DataActions":  [

                    ],
    "NotDataActions":  [

                       ],
    "AssignableScopes":  [
                             "/subscriptions/2acb0abe-d00f-4199-ba56-19f2304d2ab6"
                         ]
}'


echo "Creating role and user..."
# upsert role
az role definition create --role-definition "${elephantRole}" >/dev/null 2>&1 ||  az role definition update --role-definition "${elephantRole}"

# create user with that role limiting scope to just the resource group
USERDEETS=$(az ad sp create-for-rbac --role "${ROLENAME}" --scope /subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${resourcegroup})

# extract details
azureClientId=$(echo "$USERDEETS" | jq -r .appId)
azurePassword=$(echo "$USERDEETS" | jq -r .password)

# name the elephant
elephantName="${vnetName}-elephant"


echo "Launching the elephant."
# launch the elephant
az group deployment create -g "$resourcegroup" \
	--template-uri "$TEMPLATE_URI" \
	--parameters "elephantVMName=${elephantName}" \
	--parameters "nuToken=${nutoken}" \
	--parameters "azureClientId=${azureClientId}" \
	--parameters "azurePassword=${azurePassword}" \
	--parameters "elephantVNETName=${vnetname}" \
	--parameters "elephantSubnetName=${subnetName}"
