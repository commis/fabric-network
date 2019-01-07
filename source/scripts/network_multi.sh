#!/bin/bash
#
# Copyright IBM Corp. All Rights Reserved.
#
# SPDX-License-Identifier: Apache-2.0
#

#set -ux

[[ "$(uname -s | grep Darwin)" == "Darwin" ]] && SED_OPTS="-it" || SED_OPTS="-i"
[[ "$(uname -s | grep Darwin)" == "Darwin" ]] && XARGS_OPTS="-t" || XARGS_OPTS="-ti"

HOSTS_FILE="inventory"
MULTI_CFG_FOLDER=""
SHELL_LEFT_FOLDER=$(cd `dirname $(readlink -f "$0")`/..; pwd)
COMPOSE_E2E_FILE=docker-compose-e2e.yaml
COMPOSE_PEER_FILE=docker-compose-e2e-peer.yaml

REMOTE_USER=$(grep 'REMOTE_USER' ${SHELL_LEFT_FOLDER}/.env |cut -d= -f2)
REMOTE_PASSWORD=$(grep 'REMOTE_PASSWORD' ${SHELL_LEFT_FOLDER}/.env |cut -d= -f2)
REMOTE_SCRIPTDIR=/opt/fabric-multi
REMOTE_GOPATH=/tmp/fabric-multi
REMOTE_NETWORK_NAME=$(basename ${REMOTE_SCRIPTDIR})_default

function printHelp () {
    echo "Usage: ./`basename $0` [-t up|down|upgrade] [-c channel-name] [-o timeout]"
}

function sshConn() {
    sudo sshpass -p ${REMOTE_PASSWORD} ssh -o 'MACs umac-64@openssh.com' ${REMOTE_USER}@${1} "$2"
}

function copyDockercompose() {
    echo "Copy docker compose '$2'"
    sudo sshpass -p ${REMOTE_PASSWORD} ssh -o 'MACs umac-64@openssh.com' ${REMOTE_USER}@${1} "mkdir -p ${REMOTE_SCRIPTDIR}"
    sudo sshpass -p ${REMOTE_PASSWORD} scp -r -o 'MACs umac-64@openssh.com' -c aes192-cbc $2 ${REMOTE_USER}@${1}:${REMOTE_SCRIPTDIR}
}

function copyChaincode() {
    echo "Copy chaincode '$2'"
    sudo sshpass -p ${REMOTE_PASSWORD} ssh -o 'MACs umac-64@openssh.com' ${REMOTE_USER}@${1} "mkdir -p ${3}"
    sudo sshpass -p ${REMOTE_PASSWORD} scp -r -o 'MACs umac-64@openssh.com' -c aes192-cbc $2/* ${REMOTE_USER}@${1}:${3}
}

function setEnvGopathAndCheckChaincode() {
    GO_CHAINCODE=${GOPATH}/src/$(grep 'CHAINCODE_INSTALL' .env |awk -F'=' '{print $2}')
    echo "chaincode path: ${GO_CHAINCODE}"
    if [ ! -d "${GO_CHAINCODE}" ]; then
        echo "please modify 'CHAINCODE_INSTALL' in .env and make sure chaincode in GOPATH/src"
        exit 1
    fi

    sed ${SED_OPTS} "s|LOCAL_GOPATH=\$GOPATH|LOCAL_GOPATH=$REMOTE_GOPATH|g" .env
}

function unsetEnvGopath() {
    sed ${SED_OPTS} "s|LOCAL_GOPATH=$REMOTE_GOPATH|LOCAL_GOPATH=\$GOPATH|g" .env
}

function processNetworkName() {
    CONFIG_FILE=$1
    if [ -f "${CONFIG_FILE}" ]; then
        NETWORK_NAME_OLD=$(cat $CONFIG_FILE |grep 'CORE_VM_DOCKER_HOSTCONFIG_NETWORKMODE')
        if [ "${UP_DOWN}" == "down" ]; then
            NETWORK_NAME_NEW=$(echo ${NETWORK_NAME_OLD} |sed 's/[# ]\+-/      -/g')
        else
            NETWORK_NAME_NEW="#"${NETWORK_NAME_OLD}
        fi
        sed ${SED_OPTS} "s/${NETWORK_NAME_OLD}/${NETWORK_NAME_NEW}/g" ${CONFIG_FILE}
    fi
}

function updatePrivateKey() {
    CONFIG_FILE=$1

    CURRENT_DIR=`pwd`
    cd ${SHELL_LEFT_FOLDER}/crypto-config/peerOrganizations/yzhorg.net/ca/
    PRIV_KEY=$(ls *_sk)
    cd $CURRENT_DIR
    sed $SED_OPTS "s/CA1_PRIVATE_KEY/${PRIV_KEY}/g" ${CONFIG_FILE}
}

function updatePeerList() {
    CONFIG_FILE=$1

    PEER_LIST_OLD=$(cat $CONFIG_FILE |grep 'FABRIC_PEERS_LIST=')
    PEER_LIST_NEW=${PEER_LIST_OLD%=*}=$(cat ${HOSTS_FILE} |grep peer |cut -d= -f1 |sed 's/peer//g' |xargs)
    sed ${SED_OPTS} "s/${PEER_LIST_OLD}/${PEER_LIST_NEW}/g" ${CONFIG_FILE}
}

function updatePeerDockerCompose() {
    CONTAIN_NAME=$1
    CONFIG_FILE=$2

    NEW_PEER_DIR=peer$(echo ${CONTAIN_NAME}|awk -Fr '{print $2-1}')
    sed ${SED_OPTS} "s/peerName/${CONTAIN_NAME}/g" ${CONFIG_FILE}
    sed ${SED_OPTS} "s/peer0.yzhorg.net/${NEW_PEER_DIR}.yzhorg.net/g" ${CONFIG_FILE}
}

function adjustExtraHosts() {
    CONFIG_FILE=$1
    DONE_RECORD=$2

    for node in $(cat ${HOSTS_FILE} |xargs); do
        sed ${SED_OPTS} "/extra_hosts/a\      - ${node%=*}:${node#*=}" ${CONFIG_FILE}
        if [[ ${node%=*} == orderer ]]; then
            sed ${SED_OPTS} "/extra_hosts/a\      - ca:${node#*=}" ${CONFIG_FILE}
        elif [[ ${node%=*} =~ peer ]]; then
            peerName=${node%=*}
            #sed ${SED_OPTS} "/extra_hosts/a\      - couchdb${peerName#*peer}:${node#*=}" ${CONFIG_FILE}
        fi
    done
}

function initRemoteNetwork() {
    setEnvGopathAndCheckChaincode

    CHAINCODE=$(grep 'CHAINCODE_PACKAGE_REMOTE' ${SHELL_LEFT_FOLDER}/.env |awk -F'=' '{print $2}')
    LOCAL_CHAINCODE=${GOPATH}/${CHAINCODE}
    REMOTE_CHAINCODE=${REMOTE_GOPATH}/${CHAINCODE}

    DONE_NODES=/tmp/nodes.txt; touch ${DONE_NODES}
    for DST in $(cat ${HOSTS_FILE}); do
        echo "Do node : ${DST} ..."
        if [ -z $(cat ${DONE_NODES} |grep ${DST#*=}) ]; then
            copyDockercompose ${DST#*=} 'crypto-config .env'
            echo ${DST#*=} >> ${DONE_NODES}
        fi
        if [[ "$DST" =~ "orderer" ]];then
            copyChaincode ${DST#*=} ${LOCAL_CHAINCODE#*=} ${REMOTE_CHAINCODE#*=}
            copyDockercompose ${DST#*=} "scripts"

            TEMP_FILE=/tmp/${COMPOSE_E2E_FILE}
            cp -f ${MULTI_CFG_FOLDER}/docker-compose-e2e-template.yaml ${TEMP_FILE}

            updatePrivateKey "${TEMP_FILE}"
            updatePeerList "${TEMP_FILE}"

        elif [[ "$DST" =~ "peer" ]];then
            copyDockercompose ${DST#*=} "base"

            TEMP_FILE=/tmp/${COMPOSE_PEER_FILE}
            cp -f ${MULTI_CFG_FOLDER}/${COMPOSE_PEER_FILE} ${TEMP_FILE}

            updatePeerDockerCompose ${DST%=*} "${TEMP_FILE}"
        fi

        adjustExtraHosts "${TEMP_FILE}" "${DONE_NODES}"
        copyDockercompose ${DST#*=} "${TEMP_FILE}"
    done
    rm -f ${TEMP_FILE} ${DONE_NODES}
}

function startRemoteNetwork() {
    for DST in $(cat ${HOSTS_FILE} |sort -r); do
        if [[ "$DST" =~ "orderer" ]]; then
            COMPOSE_FILE=${COMPOSE_E2E_FILE}
            sleep 5
        elif [[ "$DST" =~ "peer" ]]; then
            COMPOSE_FILE=${COMPOSE_PEER_FILE}
        fi
        EXECUTE_CMD="GOPATH=${REMOTE_GOPATH} CHANNEL_NAME=$CH_NAME TIMEOUT=$CLI_TIMEOUT docker-compose -f $COMPOSE_FILE up -d"
        sshConn ${DST#*=} "cd ${REMOTE_SCRIPTDIR}; ${EXECUTE_CMD}"
    done
}

function networkUp () {
#    if [ -d "${SHELL_LEFT_FOLDER}/crypto-config" ]; then
#        echo "crypto-config directory already exists."
#    else
#        source ${SHELL_LEFT_FOLDER}/generateArtifacts.sh $CH_NAME
#    fi
#
#    processNetworkName ${SHELL_LEFT_FOLDER}/base/peer-base.yaml
#
#    initRemoteNetwork
    startRemoteNetwork
}

function networkUpgrade () {
    if [ ! -d "${backup_folder}/crypto" ]; then
        echo "crypto-upgrade directory not exists."
        exit 1
    fi

    rm -rf ${SHELL_LEFT_FOLDER}/crypto-config; cp -r ${backup_folder}/crypto ${SHELL_LEFT_FOLDER}/crypto-config

    processNetworkName ${SHELL_LEFT_FOLDER}/base/peer-base.yaml

    initRemoteNetwork
    startRemoteNetwork
}

function networkDown () {
    for DST in `cat "$HOSTS_FILE" |sort -r`; do
        if [[ "$DST" =~ "orderer" ]]; then
            COMPOSE_FILE=${COMPOSE_E2E_FILE}
        elif [[ "$DST" =~ "peer" ]]; then
            COMPOSE_FILE=${COMPOSE_PEER_FILE}
        fi

        EXECUTE_CMD="""
            if [[ -f ${REMOTE_SCRIPTDIR}/$COMPOSE_FILE ]]; then
                cd ${REMOTE_SCRIPTDIR}
                TIMEOUT=$CLI_TIMEOUT docker-compose -f $COMPOSE_FILE down
                docker ps -aq |xargs ${XARGS_OPTS} docker rm -f {}
                docker images | grep 'dev\|none\|test-vp\|peer[0-9]-' | awk '{print \$3}' |xargs ${XARGS_OPTS} docker rmi -f {}
                docker volume prune -f
            fi
#            rm -rf ${REMOTE_GOPATH}
#            rm -rf ${REMOTE_SCRIPTDIR}
        """
        sshConn ${DST#*=} "${EXECUTE_CMD}"
    done

#    processNetworkName ${SHELL_LEFT_FOLDER}/base/peer-base.yaml
#    unsetEnvGopath

    # remove orderer block and other channel configuration transactions and certs
#    rm -rf ${SHELL_LEFT_FOLDER}/crypto-config
#    rm -rf ${SHELL_LEFT_FOLDER}/${COMPOSE_E2E_FILE}
#    rm -rf ${SHELL_LEFT_FOLDER}/*.yamlt
#    rm -rf ${SHELL_LEFT_FOLDER}/scripts/*.pb
#    rm -rf ${SHELL_LEFT_FOLDER}/scripts/log.txt
}

function multiUpgradeUp() {
    echo "Support upgrade node list:"
    echo "  1 : from fabric-1.0.1"

    declare -A dic=(
        [1]="fabric-1.0.1"
        )

    read -p "Please input your select: " num
    case "$num" in
        *[!1-1]*)
            multiUpgradeUp
            ;;
        1)
            networkUpgrade "upgrade/${dic[$num]}"
            ;;
    esac
}

function selectMultiNetworkNode() {
    echo "Support node list:"
    echo "  1 : multi 1 org, 1 orderer, 4 peer"

    declare -A dic=(
        [1]="multi_1org_1orderer_peer"
        )

    read -p "Please input your select: " num
    case "$num" in
        *[!1-1]*)
            selectMultiNetworkNode
            ;;
        *)
            MULTI_CFG_FOLDER=${SHELL_LEFT_FOLDER}/nodes/${dic[$num]}
            HOSTS_FILE=${MULTI_CFG_FOLDER}/${HOSTS_FILE}
            ;;
    esac
}

function execute() {
    selectMultiNetworkNode

    echo "install node: ${MULTI_CFG_FOLDER}"
    case ${UP_DOWN} in
        "up")
            networkUp
            ;;
        "down")
            networkDown
            ;;
        "upgrade")
            networkUpgrade
            ;;
        "restart")
            networkDown
            networkUp
            ;;
        ?)
            printHelp
            exit 1
    esac
}


function validateArgs () {
    if [ -z "${UP_DOWN}" ]; then
        echo "Option up/down/upgrade/restart not mentioned"
        printHelp
        exit 1
    fi
}

# parse script args
while getopts "t:c:o" OPTION; do
    case ${OPTION} in
    t)
        UP_DOWN=$OPTARG
        validateArgs
        ;;
    c)
        CH_NAME=$OPTARG
        if [[ "${UP_DOWN}" != "down" ]] && [[ -z "${CH_NAME}" ]]; then
            echo "Option channel-name not mentioned"
            printHelp
            exit 1
        fi
        ;;
    o)
        CLI_TIMEOUT=$OPTARG
        if [[ $num =~ ^[0-9]+$ ]]; then
            echo "Option timeout is not number"
            printHelp
            exit 1
        fi
        ;;
    ?)
        printHelp
        exit 1
    esac
done

validateArgs
: ${CH_NAME:="yzhchannel"}
: ${CLI_TIMEOUT:="3600000"}
echo "shell dir: ${SHELL_LEFT_FOLDER}"
echo "execute args: ${UP_DOWN} ${CH_NAME} ${CLI_TIMEOUT}"
execute
