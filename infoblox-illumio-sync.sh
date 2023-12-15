#!/bin/bash
#
#infoblox to illumio sync
version="0.0.3"
#
#Licensed under the Apache License, Version 2.0 (the "License"); you may not
#use this file except in compliance with the License. You may obtain a copy of
#the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
#Unless required by applicable law or agreed to in writing, software
#distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
#WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
#License for the specific language governing permissions and limitations under
#the License.
#

usage(){
    cat << EOF
infoblox-illumio-sync.sh - creates illumio PCE IP lists and unmanaged workloads from infoblox networks and used ip address records
https://github.com/code7a/infoblox-illumio-sync

jq is required to parse results
https://stedolan.github.io/jq/

usage: ./infoblox-illumio-sync.sh [options]

options:
    -n, --get-networks                  get infoblox networks
    -i, --get-ips                       get infoblox ip addresses
    -l, --create-ip-lists               create illumio pce ip lists from infoblox networks
    -u, --create-unmanaged-workloads    create illumio pce unmanaged workloads from infoblox ip addresses
    -v, --version                       returns version
    -h, --help                          returns help message

examples:
    ./infoblox-illumio-sync.sh --get-networks
    ./infoblox-illumio-sync.sh -i
    ./infoblox-illumio-sync.sh --create-ip-lists
    ./infoblox-illumio-sync.sh -l -u
    ./infoblox-illumio-sync.sh --create-unmanaged-workloads --create-ip-lists
EOF
}

get_jq_version(){
    jq_version=$(jq --version)
    if [ $(echo $?) -ne 0 ]; then
        echo "jq application not found. jq is a command line JSON processor and is used to process and filter JSON inputs."
        echo "Reference: https://stedolan.github.io/jq/"
        echo "Please install jq, i.e. yum install jq"
        exit 1
    fi
}

get_version(){
    echo "infoblox-illumio-sync v"$version
}

get_config_yml(){
    source $BASEDIR/.illumio_config.yml >/dev/null 2>&1 || get_illumio_vars
    source $BASEDIR/.infoblox_config.yml >/dev/null 2>&1 || get_infoblox_vars
}

get_illumio_vars(){
    echo ""
    read -p "Enter illumio PCE domain: " ILLUMIO_PCE_DOMAIN
    read -p "Enter illumio PCE port: " ILLUMIO_PCE_PORT
    read -p "Enter illumio PCE organization ID: " ILLUMIO_PCE_ORG_ID
    read -p "Enter illumio PCE API username: " ILLUMIO_PCE_API_USERNAME
    echo -n "Enter illumio PCE API secret: " && read -s ILLUMIO_PCE_API_SECRET && echo ""
    cat << EOF > $BASEDIR/.illumio_config.yml
export ILLUMIO_PCE_DOMAIN=$ILLUMIO_PCE_DOMAIN
export ILLUMIO_PCE_PORT=$ILLUMIO_PCE_PORT
export ILLUMIO_PCE_ORG_ID=$ILLUMIO_PCE_ORG_ID
export ILLUMIO_PCE_API_USERNAME=$ILLUMIO_PCE_API_USERNAME
export ILLUMIO_PCE_API_SECRET=$ILLUMIO_PCE_API_SECRET
EOF
}

get_infoblox_vars(){
    read -p "Enter infoblox appliance IP or hostname: " INFOBLOX_HOST
    read -p "Enter infoblox username: " INFOBLOX_USERNAME
    echo -n "Enter infoblox password: " && read -s INFOBLOX_PASSWORD && echo ""
    echo ""
    cat << EOF > $BASEDIR/.infoblox_config.yml
export INFOBLOX_HOST=$INFOBLOX_HOST
export INFOBLOX_USERNAME=$INFOBLOX_USERNAME
export INFOBLOX_PASSWORD=$INFOBLOX_PASSWORD
EOF
}

get_infoblox_networks(){
    #todo: account for nested networks
    INFOBLOX_VERSION=$(curl -s -k "https://$INFOBLOX_USERNAME:$INFOBLOX_PASSWORD@$INFOBLOX_HOST/wapidoc/index.html" | grep 'The current WAPI version is' | cut -d' ' -f8 | cut -d. -f1-2)
    INFOBLOX_NETWORKS=$(curl -s -k "https://$INFOBLOX_USERNAME:$INFOBLOX_PASSWORD@$INFOBLOX_HOST/wapi/v$INFOBLOX_VERSION/network" | jq -c -r '.[]|{comment,network}')
    INFOBLOX_NETWORKS_GET_FILENAME="INFOBLOX-NETWORKS-GET-$(date +%Y.%m.%dT%H.%M.%S).log"
    echo $INFOBLOX_NETWORKS > $INFOBLOX_NETWORKS_GET_FILENAME
    echo -e "\nFound infoblox networks > $INFOBLOX_NETWORKS_GET_FILENAME"
}

get_infoblox_ip_addresses(){
    #todo: account for nested networks
    #todo: allow for max results input, set to 100k, notify if hit
    INFOBLOX_VERSION=$(curl -s -k "https://$INFOBLOX_USERNAME:$INFOBLOX_PASSWORD@$INFOBLOX_HOST/wapidoc/index.html" | grep 'The current WAPI version is' | cut -d' ' -f8 | cut -d. -f1-2)
    INFOBLOX_NETWORKS=($(curl -s -k "https://$INFOBLOX_USERNAME:$INFOBLOX_PASSWORD@$INFOBLOX_HOST/wapi/v$INFOBLOX_VERSION/network" | jq -r .[].network))
    #get infoblox ip address objects, exclude type dhcp reservations
    INFOBLOX_OBJECTS=()
    for NETWORK in "${INFOBLOX_NETWORKS[@]}";do
        INFOBLOX_OBJECTS+=($(curl -s -k "https://$INFOBLOX_USERNAME:$INFOBLOX_PASSWORD@$INFOBLOX_HOST/wapi/v$INFOBLOX_VERSION/ipv4address?network=$NETWORK&_max_results=100000&status=USED" | jq -c -r '.[]|select(.types[]=="RESERVATION"|not)|{ip_address,names}'))
    done
    INFOBLOX_OBJECTS_GET_FILENAME="INFOBLOX-OBJECTS-GET-$(date +%Y.%m.%dT%H.%M.%S).log"
    echo ${INFOBLOX_OBJECTS[@]} > $INFOBLOX_OBJECTS_GET_FILENAME
    echo -e "\nFound infoblox ip address records > $INFOBLOX_OBJECTS_GET_FILENAME"
}

create_illumio_ip_lists(){
    get_infoblox_networks
    #loop through each network
    echo $INFOBLOX_NETWORKS | jq -c -r | while read OBJECT; do
        INFOBLOX_NETWORK_NAME=$(echo $OBJECT | jq -c -r .comment)
        INFOBLOX_NETWORK_CIDR=$(echo $OBJECT | jq -c -r .network)
        ILLUMIO_PCE_IP_LISTS=$(curl -s "https://$ILLUMIO_PCE_API_USERNAME:$ILLUMIO_PCE_API_SECRET@$ILLUMIO_PCE_DOMAIN:$ILLUMIO_PCE_PORT/api/v2/orgs/$ILLUMIO_PCE_ORG_ID/sec_policy/draft/ip_lists?ip_address=$INFOBLOX_NETWORK_CIDR" | jq '.[]|select(.ip_ranges[].from_ip=="0.0.0.0/0"|not)')
        #if no ip lists, create ip list
        if [ ! -n "$ILLUMIO_PCE_IP_LISTS" ]; then
            #if comment is empty, update name with cidr
            if [ ! -n "$INFOBLOX_NETWORK_NAME" ]; then
                INFOBLOX_NETWORK_NAME=$INFOBLOX_NETWORK_CIDR
            fi
            echo -e "\nIP list drafted:"
            body='{"name":"IPL-'$INFOBLOX_NETWORK_NAME'","description":"Created by infoblox-illumio-sync.sh","ip_ranges":[{"from_ip":"'$INFOBLOX_NETWORK_CIDR'"}],"fqdns":[]}'
            curl -X POST "https://$ILLUMIO_PCE_API_USERNAME:$ILLUMIO_PCE_API_SECRET@$ILLUMIO_PCE_DOMAIN:$ILLUMIO_PCE_PORT/api/v2/orgs/$ILLUMIO_PCE_ORG_ID/sec_policy/draft/ip_lists" -H 'content-type: application/json' --data "$body"
            echo ""
        fi
    done
}

create_illumio_unmanaged_workloads(){
    get_infoblox_ip_addresses
    for OBJECT in "${INFOBLOX_OBJECTS[@]}"; do
        INFOBLOX_OBJECT_IP_ADDRESS=$(echo $OBJECT | jq -c -r .ip_address)
        INFOBLOX_OBJECT_NAME=$(echo $OBJECT | jq -c -r .names[])
        #get workload by ip address
        WORKLOAD=$(curl -s "https://$ILLUMIO_PCE_API_USERNAME:$ILLUMIO_PCE_API_SECRET@$ILLUMIO_PCE_DOMAIN:$ILLUMIO_PCE_PORT/api/v2/orgs/$ILLUMIO_PCE_ORG_ID/workloads?ip_address=$INFOBLOX_OBJECT_IP_ADDRESS" | jq -c -r .[])
        #if no workload, create unmanaged workload
        if [ ! -n "$WORKLOAD" ]; then
            #if no name, update name with ip address
            if [ ! -n "$INFOBLOX_OBJECT_NAME" ]; then
                INFOBLOX_OBJECT_NAME="umw-$INFOBLOX_OBJECT_IP_ADDRESS"
            fi
            echo -e "\nUnmanaged workload created:"
            body='{"name":"'$INFOBLOX_OBJECT_NAME'","description":"Created by infoblox-illumio-sync.sh","hostname":"'$INFOBLOX_OBJECT_NAME'","interfaces":[{"address":"'$INFOBLOX_OBJECT_IP_ADDRESS'","name":"umw0"}]}'
            curl -X POST "https://$ILLUMIO_PCE_API_USERNAME:$ILLUMIO_PCE_API_SECRET@$ILLUMIO_PCE_DOMAIN:$ILLUMIO_PCE_PORT/api/v2/orgs/$ILLUMIO_PCE_ORG_ID/workloads" -H 'content-type: application/json' --data "$body"
            echo ""
        fi
    done
}

BASEDIR=$(dirname $0)

get_jq_version

get_config_yml

while true
do
    #todo: account for if no argument was provided
    if [ "$1" == "" ]; then
        break
    fi
    case $1 in
        -n|--get-networks)
            get_infoblox_networks
            exit 0
            ;;
        -i|--get-ips)
            get_infoblox_ip_addresses
            exit 0
            ;;
        -l|--create-ip-lists)
            create_illumio_ip_lists
            shift
            ;;
        -u|--create-unmanaged-workloads)
            create_illumio_unmanaged_workloads
            shift
            ;;
        -v|--version)
            get_version
            exit 0
            ;;
        -h|--help)
            usage
            exit 1
            ;;
        -*)
            echo -e "\n$0: ERROR: Unknown option: $1" >&2
            usage
            exit 1
            ;;
        *)
            echo -e "\n$0: ERROR: Unknown argument: $1" >&2
            usage
            exit 1
            ;;
    esac
done

exit 0