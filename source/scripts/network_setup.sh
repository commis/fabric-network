#!/usr/bin/bash

set -e

[[ "$(uname -s | grep Darwin)" == "Darwin" ]] && SED_OPTS="-it" || SED_OPTS="-i"

# all global environment parameter
SOURCE_ROOT=$(cd `dirname $(readlink -f "$0")`/.. && pwd)
COMPOSE_FILE=${SOURCE_ROOT}/docker-compose-e2e.yaml

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
while getopts "t:c:o" OPTION; do
    case ${OPTION} in
    t)
        OP_METHOD=$OPTARG
        validateArgs
        ;;
    c)
        CH_NAME=$OPTARG
        if [[ "${OP_METHOD}" != "down" ]] && [[ -z "${CH_NAME}" ]]; then
            echo "Option channel-name not mentioned"
            printHelp
        fi
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

function clearContainers() {
    CONTAINER_IDS=$(docker ps -aq)
    if [[ -z "$CONTAINER_IDS" || "$CONTAINER_IDS" = " " ]]; then
        echo "---- No containers available for deletion ----"
    else
        docker rm -f $CONTAINER_IDS
    fi
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

function networkUp() {
    cp ${SOURCE_ROOT}/template/single/docker-compose-e2e-template.yaml ${SOURCE_ROOT}/docker-compose-e2e.yaml

    if [[ -d "${SOURCE_ROOT}/crypto-config" ]]; then
        echo "crypto-config directory already exists."
    else
        source generateArtifacts.sh $CH_NAME
    fi

    cd ${SOURCE_ROOT}/scripts
    updateNetworkName ${SOURCE_ROOT}/base/peer-base.yaml
    CHANNEL_NAME=$CH_NAME TIMEOUT=$CLI_TIMEOUT docker-compose -f $COMPOSE_FILE up -d 2>&1
    if [[ $? -ne 0 ]]; then
      echo "ERROR !!!! Unable to pull the images "
      exit 1
    fi
    docker logs -f cli
}

function networkDown() {
    if [[ -f "${COMPOSE_FILE}" ]]; then
        TIMEOUT=$CLI_TIMEOUT docker-compose -f ${COMPOSE_FILE} down --volumes 2>&1
    fi

    #Cleanup the chaincode containers
    clearContainers

    #Cleanup images
    removeUnwantedImages

    unsetEnvGopath

    # remove orderer block and other channel configuration transactions and certs
    sudo rm -rf ${SOURCE_ROOT}/crypto-config ${SOURCE_ROOT}/base/crypto-config
    sudo rm -rf ${SOURCE_ROOT}/channel-artifacts/*
    sudo rm -f ${COMPOSE_FILE} ${SOURCE_ROOT}/*.yamlt
    sudo rm -f ${SOURCE_ROOT}/*.pb ${SOURCE_ROOT}/scripts/log.txt
    # docker volume prune -f
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

function executeSignle() {
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

function executeCommand() {
    echo "Support setup type:"
    echo "  1 : Standalone"
    echo "  2 : Multimachine"

    read -p "Please input your select: " num
    case "$num" in
        *[!1-2]*)
            executeCommand
            ;;
        1)
            executeSignle
            ;;
        2)
            ${SOURCE_ROOT}/scripts/network_multi.sh -t ${OP_METHOD} -c ${CH_NAME}
            ;;
    esac
}


validateArgs
: ${CH_NAME:="yzhchannel"}
: ${CLI_TIMEOUT:="600000"}
chmod -R a+x ${SOURCE_ROOT}/tools >& /dev/null
echo "root dir: ${SOURCE_ROOT}"
echo "execute args: ${OP_METHOD} ${CH_NAME} ${CLI_TIMEOUT}"
executeCommand
