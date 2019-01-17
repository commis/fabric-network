#!/usr/bin/bash

set -e

[[ "$(uname -s | grep Darwin)" == "Darwin" ]] && SED_OPTS="-it" || SED_OPTS="-i"

# all global environment parameter
SOURCE_ROOT=$(cd `dirname $(readlink -f "$0")`/.. && pwd)
REMOTE_USER=$(grep 'REMOTE_USER' ${SOURCE_ROOT}/scripts/.env |cut -d= -f2)
REMOTE_PASSWORD=$(grep 'REMOTE_PASSWORD' ${SOURCE_ROOT}/scripts/.env |cut -d= -f2)
REMOTE_SCRIPTDIR=/opt/fabric-data
COMPOSE_FILE=${SOURCE_ROOT}/docker-compose-cli.yaml
OPENSSH_OPTS="MACs umac-64@openssh.com"
ORG_PEER_JSON=$(grep '^ORG_PEER_SET' ${SOURCE_ROOT}/scripts/.env |awk -F'=' '{print $2}')
ADDR_NODE_CLI=$(grep '^ADDR_CLI' ${SOURCE_ROOT}/scripts/.env |awk -F'=' '{print $2}')

[[ "$(uname -s | grep Darwin)" == "Darwin" ]] && OPTS="-it" || OPTS="-i"

function printHelp() {
    echo "Usage: ./`basename $0` [-t up|down] [-c channel-name] [-o timeout]"
    exit 1
}

function validateArgs() {
    if [[ -z "${OP_METHOD}" ]]; then
        echo "Option up/down/restart not mentioned"
        printHelp
    fi
}

# parse script args
while getopts ":t:o:" OPTION; do
    case ${OPTION} in
    t)
        OP_METHOD=$OPTARG
        validateArgs
        ;;
    o)
        CLI_TIMEOUT=$OPTARG
        if [[ $num =~ ^[0-9]+$ ]]; then
            echo "Option timeout is not number"
            printHelp
        fi
        ;;
    ?)
        printHelp
    esac
done

function sshConn() {
    sudo sshpass -p ${REMOTE_PASSWORD} ssh -o "${OPENSSH_OPTS}" ${REMOTE_USER}@${1} "$2"
}

function copyDockercompose() {
    echo "Copy docker compose '$2'"
    sudo sshpass -p ${REMOTE_PASSWORD} ssh -o "${OPENSSH_OPTS}" ${REMOTE_USER}@${1} "mkdir -p ${REMOTE_SCRIPTDIR}"
    sudo sshpass -p ${REMOTE_PASSWORD} scp -r -o "${OPENSSH_OPTS}" -c aes192-cbc $2 ${REMOTE_USER}@${1}:${REMOTE_SCRIPTDIR}
}

function copyChaincode() {
    echo "Copy chaincode '$2'"
    sudo sshpass -p ${REMOTE_PASSWORD} ssh -o "${OPENSSH_OPTS}" ${REMOTE_USER}@${1} "mkdir -p ${3}"
    sudo sshpass -p ${REMOTE_PASSWORD} scp -r -o "${OPENSSH_OPTS}" -c aes192-cbc $2/* ${REMOTE_USER}@${1}:${3}
}

function clearContainers() {
    CONTAINER_IDS=$(docker ps -aq)
    if [[ -z "$CONTAINER_IDS" || "$CONTAINER_IDS" = " " ]]; then
        echo "---- No containers available for deletion ----"
    else
        docker rm -f $CONTAINER_IDS
    fi
    docker volume prune -f
}

function removeUnwantedImages() {
    DOCKER_IMAGE_IDS=$(docker images | grep "dev\|none\|test-vp\|peer[0-9]-" | awk '{print $3}')
    if [[ -z "$DOCKER_IMAGE_IDS" || "$DOCKER_IMAGE_IDS" = " " ]]; then
        echo "---- No images available for deletion ----"
    else
        docker rmi -f $DOCKER_IMAGE_IDS
    fi
}

function updateNetworkName() {
    CONFIG_FILE=$1
    ENV_KEY_NAME=CORE_VM_DOCKER_HOSTCONFIG_NETWORKMODE

    NETWORK_NAME_NEW=${ENV_KEY_NAME}=source_default
    NETWORK_NAME_OLD=${ENV_KEY_NAME}=$(cat $CONFIG_FILE |grep $ENV_KEY_NAME |awk -F= '{print $2}')
    sed ${SED_OPTS} "s/${NETWORK_NAME_OLD}/${NETWORK_NAME_NEW}/g" ${CONFIG_FILE}
}

function replacePort() {
    compose_file=$1
    number=$2
    array=(`echo $3|sed 's/:/ /g'`)

    first=${array[0]}
    total=$(echo $first |awk '{print length($0)-1}')
    realPort=$(expr ${first:0:1} + $number)${first:1:$total}:${array[1]}

    sed $OPTS "s/${3}/${realPort}/g" $compose_file
}

function replacePeerComposeParameter() {
    compose_file=$1
    org_id=$2
    peer_id=$3
    counter=$4

    sed $OPTS "s/PeerName/peer${peer_id}Org${org_id}/g" $compose_file
    sed $OPTS "s/DBName/couchdb_Peer${peer_id}Org${org_id}/g" $compose_file
    sed $OPTS "s/PEER_MSPID_NAME/PEER_MSPID_${org_id}/g" $compose_file
    sed $OPTS "s/PEER_DOMAIN_NAME/PEER_DOMAIN_${org_id}/g" $compose_file

    addr_peer=$(grep "^ADDR_ORG_${org_id}" ${SOURCE_ROOT}/scripts/.env |awk -F'=' '{print $2}')
    if [[ "$ADDR_NODE_CLI" != "$addr_peer" ]]; then
        replacePort $compose_file $counter "5984:5984"
        replacePort $compose_file $counter "7051:7051"
        replacePort $compose_file $counter "7052:7052"
        replacePort $compose_file $counter "7053:7053"
    fi
}

function buildAllPeerNodeCompose() {
    orgs=$(echo $ORG_PEER_JSON |jq ".orgs"|sed 's/\"//g')
    peers=$(echo $ORG_PEER_JSON |jq ".peers"|sed 's/\"//g')

    counter=0
    for org in ${orgs}; do
        for peer in ${peers}; do
            peer_file=${SOURCE_ROOT}//docker-compose-org${org}_peer${peer}.yaml
            cp ${SOURCE_ROOT}/template/docker-compose-peer-template.yaml ${peer_file}
            replacePeerComposeParameter ${peer_file} ${org} $peer $counter
            counter=`expr ${counter} + 1`
        done
    done
}

function startDockerContainer() {
    compose_file=$1
    TIMEOUT=$CLI_TIMEOUT docker-compose -f $compose_file up -d 2>&1
    if [[ $? -ne 0 ]]; then
      echo "ERROR !!!! Unable to pull the images. ${compose_file}"
      exit 1
    fi
}

function startAllPeerNode() {
    orgs=$(echo $ORG_PEER_JSON |jq ".orgs"|sed 's/\"//g')
    peers=$(echo $ORG_PEER_JSON |jq ".peers"|sed 's/\"//g')

    counter=0
    for org in ${orgs}; do
        for peer in ${peers}; do
            peer_file=${SOURCE_ROOT}/docker-compose-org${org}_peer${peer}.yaml
            startDockerContainer ${peer_file}
        done
    done
}

function networkUp() {
    cp ${SOURCE_ROOT}/template/docker-compose-cli-template.yaml ${COMPOSE_FILE}

    if [[ -d "${SOURCE_ROOT}/crypto-config" ]]; then
        echo "crypto-config directory already exists."
    else
        source generateArtifacts.sh
    fi

    cd ${SOURCE_ROOT}/scripts
    updateNetworkName ${SOURCE_ROOT}/base/peer-base.yaml
    buildAllPeerNodeCompose
    startAllPeerNode
    startDockerContainer $COMPOSE_FILE

    docker logs -f cli
}

function networkDown() {
    if [[ -f "${COMPOSE_FILE}" ]]; then
        TIMEOUT=$CLI_TIMEOUT docker-compose -f ${COMPOSE_FILE} down --volumes --remove-orphans 2>&1
    fi

    #Cleanup the containers and images
    clearContainers
    removeUnwantedImages

    unsetEnvGopath

    # remove orderer block and other channel configuration transactions and certs
    sudo rm -rf ${SOURCE_ROOT}/crypto-config ${SOURCE_ROOT}/base/crypto-config
    sudo rm -f ${SOURCE_ROOT}/channel-artifacts/* ${SOURCE_ROOT}/docker-compose-*
    sudo rm -f ${SOURCE_ROOT}/scripts/log.txt
}

function setEnvGopathAndCheckChaincode() {
    GO_CHAINCODE=${GOPATH}/src/$(grep '^CHAINCODE_INSTALL' ${SOURCE_ROOT}/scripts/.env |awk -F'=' '{print $2}')
    echo "chaincode path: ${GO_CHAINCODE}"
    if [[ ! -d "${GO_CHAINCODE}" ]]; then
        echo "please modify CHAINCODE_INSTALL in ${SOURCE_ROOT}/scripts/.env"
        exit 1
    fi

    sed ${SED_OPTS} "s|LOCAL_GOPATH=\$GOPATH|LOCAL_GOPATH=$GOPATH|g" ${SOURCE_ROOT}/scripts/.env
}

function unsetEnvGopath() {
    sed ${SED_OPTS} "s|LOCAL_GOPATH=$GOPATH|LOCAL_GOPATH=\$GOPATH|g" ${SOURCE_ROOT}/scripts/.env
}

function executeCommand() {
    if [[ "${OP_METHOD}" != "down" ]]; then
        setEnvGopathAndCheckChaincode
    fi
    
    case ${OP_METHOD} in
        "up")
            networkUp
            ;;
        "down")
            networkDown
            ;;
        "restart")
            networkDown
            networkUp
            ;;
        ?)
            printHelp
    esac
}

validateArgs
: ${CLI_TIMEOUT:="600000"}
chmod -R a+x ${SOURCE_ROOT}/tools >& /dev/null
echo "root dir: ${SOURCE_ROOT}"
echo "execute args: ${OP_METHOD} ${CLI_TIMEOUT}"
executeCommand
