#!/usr/bin/env bash
set -e

function cleanup {
	# Remove artifacts if failure
	if $FAILURE
	then
		if [ ! -z "$azureClientId" ]
		then
			az ad sp delete --id ${azureClientId}
		fi
		if [ ! -z "$elephantName" ]
		then
			az group deployment -g "${resourcegroup}" delete --name $elephantName}
		fi
		echo "Finished cleanup."      
	fi
}

function getchoice {
	echo "~~~~~~~~~~~~~~~~~~~~~"	
	echo " $1"
	echo "~~~~~~~~~~~~~~~~~~~~~"
	shift
	i=0
	for opt in $@
	do
		let i=i+1
		echo "$i. $opt"
	done
	local choice
	read -p "Enter choice " choice
	let choice=choice-1
	return $choice
}


trap cleanup EXIT

FAILURE=true

echo "Validating parameters..."
# Required vars
for var in nutoken
do
	if [ -z "${!var}" ]
	then
		echo "$var environment variable not set"
		exit 1
	fi
done

# Validation
if [ -z "$resourcegroup" ]
then
# Present a list of resource groups
	RGS=$(az group list)
	RGZ=$(echo "$RGS" | jq -r 'length')
	if [ $RGZ -eq 0 ]
	then
	    echo "No resource groups found."
		exit 1
	fi
	if [ $RGZ -eq 1 ]
	then
		rgNo=0
		echo "Chosing the one and only resource group"
	else
		set +e
		getchoice "Please choose the resource group that contains the vnet you want to monitor" $(echo "$RGS" | jq -r '.[].name')
		rgNo=$?
		set -e
	fi
	resourcegroup=$(echo "$RGS" | jq -r ".[$rgNo].name")
	echo "Chosen: $resourcegroup"
fi

if [ "$(az group exists --name ${resourcegroup})" != "true" ]
then
	echo "Unable to find resource group named '${resourcegroup}'"
	exit 1
fi

if [ -z "$vnetname" ]
then
# Present a list of vnets
	VNETS=$(az network vnet  list -g "${resourcegroup}")
	VNETZ=$(echo "$VNETS" | jq -r 'length')
	if [ $VNETZ -eq 0 ]
	then
	    echo "No vnets found."
		exit 1
	fi
	if [ $VNETZ -eq 1 ]
	then
		vnetNo=0
		echo "Chosing the one and only vnet"
	else
		set +e
		getchoice "Please choose a vnet for the elephant to monitor" $(echo "$VNETS" | jq -r '.[].name')
		vnetNo=$?
		set -e
	fi

	vnetname=$(echo "$VNETS" | jq -r ".[$vnetNo].name")
	echo "Chosen: $vnetname"

	if ! az network vnet show -g ${resourcegroup} -n ${vnetname} > /dev/null
	then
		echo "Unable to find vnet '${vnetname}' in resource group '${resourcegroup}'"
		exit 1
	fi
fi


if [ -z "$subnetname" ]
then
	# Present a list of subnets
	SUBNETS=$(az network vnet subnet list -g "${resourcegroup}" --vnet-name ${vnetname})
	SUBNETZ=$(echo "$SUBNETS" | jq -r 'length')
	if [ $SUBNETZ -eq 0 ]
	then
	    echo "No subnets found."
		exit 1
	fi
	if [ $SUBNETZ -eq 1 ]
	then
		subnetNo=0
		echo "Chosing the one and only subnet"
	else
		set +e
		getchoice "Please choose a subnet for the elephant" $(echo "$SUBNETS" | jq -r '.[].name')
		subnetNo=$?
		set -e
	fi
	subnetname=$(echo "$SUBNETS" | jq -r ".[$subnetNo].name")
	echo "Chosen: $subnetname"

	# subnetName=$(az network vnet subnet list -g "${resourcegroup}" --vnet-name ${vnetname} --query '[0].name' --output tsv)
	if [ -z "$subnetname" ]
	then
		echo "Unable to find a subnet to use in vnet '${vnetname}' in resource group '${resourcegroup}'"
		exit 1
	fi
fi

if [ -z "$ROLENAME"]
then
    ROLENAME="NubevaVTap"
fi

if [ -z "$ELEPHANTNAME" ]
then
    ELEPHANTNAME="elephant"
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
az role definition create --role-definition "${elephantRole}" >/dev/null 2>&1 ||  az role definition update --role-definition "${elephantRole}" >/dev/null

# create user with that role limiting scope to just the resource group
USERDEETS=$(az ad sp create-for-rbac --role "${ROLENAME}" --scope /subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${resourcegroup})

# extract details
azureClientId=$(echo "$USERDEETS" | jq -r .appId)
azurePassword=$(echo "$USERDEETS" | jq -r .password)

# name the elephant
elephantName="${vnetname}-${ELEPHANTNAME}"


echo "Launching the elephant."
# launch the elephant
az group deployment create -g "$resourcegroup" \
    --name "${elephantName}" \
	--template-uri "$TEMPLATE_URI" \
	--parameters "elephantVMName=${elephantName}" \
	--parameters "nuToken=${nutoken}" \
	--parameters "azureClientId=${azureClientId}" \
	--parameters "azurePassword=${azurePassword}" \
	--parameters "elephantVNETName=${vnetname}" \
	--parameters "elephantSubnetName=${subnetname}" >/dev/null

echo "Success."

# If we got here, don't cleanup
export FAILURE=false
