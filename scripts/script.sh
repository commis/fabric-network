#!/bin/bash
# Copyright London Stock Exchange Group All Rights Reserved.
#
# SPDX-License-Identifier: Apache-2.0
#
echo
echo " ____    _____      _      ____    _____           _____   ____    _____ "
echo "/ ___|  |_   _|    / \    |  _ \  |_   _|         | ____| |___ \  | ____|"
echo "\___ \    | |     / _ \   | |_) |   | |    _____  |  _|     __) | |  _|  "
echo " ___) |   | |    / ___ \  |  _ <    | |   |_____| | |___   / __/  | |___ "
echo "|____/    |_|   /_/   \_\ |_| \_\   |_|           |_____| |_____| |_____|"
echo

# all global environment parameter
ROOT_DIR=$(dirname $(readlink -f "$0"))
EXECUTE_LOG=${ROOT_DIR}/log.txt
ORD_DOMAIN=$(cat ${ROOT_DIR}/.env | grep '^ORDERER_DOMAIN' | awk -F'=' '{print $2}')
ORG_PEER_JSON=$(grep '^ORG_PEER_SET' ${ROOT_DIR}/.env | awk -F'=' '{print $2}')
CHANNEL_JSON=$(cat ${ROOT_DIR}/.env | grep '^CHANNEL_SET' | awk -F'=' '{print $2}')
CHANNEL_SIZE=$(echo $CHANNEL_JSON | jq 'length-1')

VERSION="$1"
CC_INSTALL="$2"
: ${VERSION:="${VERSION}"}
: ${TIMEOUT:="600000"}
COUNTER=1
MAX_RETRY=5
ORDERER_SYSCHAN_ID=e2e-orderer-syschan
CC_INSTALLED_FILE=/var/hyperledger/chaincode

if [[ -z "$CC_INSTALL" ]]; then
    echo "Please input install chaincode path relation of GOPATH"
    exit 1
fi

ORDERER_CA=/cli/crypto/ordererOrganizations/${ORD_DOMAIN}/orderers/orderer.${ORD_DOMAIN}/msp/tlscacerts/tlsca.${ORD_DOMAIN}-cert.pem
if [[ -z "$CORE_PEER_TLS_ENABLED" || "$CORE_PEER_TLS_ENABLED" == "true" ]]; then
    PEER_OPTS="--tls ${CORE_PEER_TLS_ENABLED} --cafile $ORDERER_CA"
fi

displayInfo() {
    echo "chaincode: ${CHAINCODE_NAME}"
    echo "version: ${VERSION}"
}

verifyResult() {
    if [[ $1 -ne 0 ]]; then
        echo "!!!!!!!!!!!!!!! "$2" !!!!!!!!!!!!!!!!"
        echo "================== ERROR !!! FAILED to execute End-2-End Scenario =================="
        echo
        exit 1
    fi
}

setGlobals() {
    PEER=$1
    ORG=$2

    PEER_ORG_DOMAIN=$(cat ${ROOT_DIR}/.env | grep "^PEER_DOMAIN_${ORG}" | awk -F'=' '{print $2}')
    CLI_PEER_TLS_DIR_NAME=peer${PEER}.${PEER_ORG_DOMAIN}
    CLI_SERVER_REMOTE_CFG=/cli/crypto/peerOrganizations/${PEER_ORG_DOMAIN}

    # it is must use first peer of org
    CORE_PEER_LOCALMSPID=$(cat ${ROOT_DIR}/.env | grep "^PEER_MSPID_${ORG}" | awk -F'=' '{print $2}')
    CORE_PEER_TLS_CERT_FILE=${CLI_SERVER_REMOTE_CFG}/peers/${CLI_PEER_TLS_DIR_NAME}/tls/server.crt
    CORE_PEER_TLS_KEY_FILE=${CLI_SERVER_REMOTE_CFG}/peers/${CLI_PEER_TLS_DIR_NAME}/tls/server.key
    CORE_PEER_TLS_ROOTCERT_FILE=${CLI_SERVER_REMOTE_CFG}/peers/${CLI_PEER_TLS_DIR_NAME}/tls/ca.crt
    CORE_PEER_MSPCONFIGPATH=${CLI_SERVER_REMOTE_CFG}/users/Admin@${PEER_ORG_DOMAIN}/msp
    CORE_PEER_ADDRESS=peer${PEER}Org${ORG}:7051

    # 系统环境变量设置
    # env | grep CORE
}

checkOSNAvailability() {
    setGlobals 0 1

    #Use orderer's MSP for fetching system channel config block
    CORE_PEER_LOCALMSPID=$(cat ${ROOT_DIR}/.env | grep '^ORDERER_MSPID' | awk -F'=' '{print $2}')
    CORE_PEER_TLS_ROOTCERT_FILE=$ORDERER_CA
    CORE_PEER_MSPCONFIGPATH=/cli/crypto/ordererOrganizations/${ORD_DOMAIN}/orderers/orderer.${ORD_DOMAIN}/msp

    local rc=1
    local starttime=$(date +%s)

    # continue to poll
    # we either get a successful response, or reach TIMEOUT
    while test "$(($(date +%s) - starttime))" -lt "$TIMEOUT" -a $rc -ne 0; do
        for ord in ${FABRIC_ORDERER_LIST}; do
            sleep 3
            if [[ -z "$CORE_PEER_TLS_ENABLED" || "$CORE_PEER_TLS_ENABLED" == "false" ]]; then
                peer channel fetch 0 -o $ord:7050 -c "$ORDERER_SYSCHAN_ID" >&${EXECUTE_LOG}
            else
                peer channel fetch 0 0_block.pb -o $ord:7050 -c "$ORDERER_SYSCHAN_ID" --tls --cafile $ORDERER_CA >&${EXECUTE_LOG}
            fi
            test $? -eq 0 && VALUE=$(cat ${EXECUTE_LOG} | awk '/Received block/ {print $NF}')
            test "$VALUE" = "0" && let rc=0
        done
    done
    cat ${EXECUTE_LOG}
    verifyResult $rc "Ordering Service is not available, Please try again ..."
    echo "===================== Ordering Service is up and running ===================== "
    echo
}

createChannel() {
    # create channel every org
    for index in $(seq 0 $CHANNEL_SIZE); do
        ch_name=$(echo $CHANNEL_JSON | jq ".[$index].name" | sed 's/\"//g')
        org=$(echo $CHANNEL_JSON | jq ".[$index].orgs" | sed 's/\"//g' | awk '{print $1}')
        peer=$(echo $CHANNEL_JSON | jq ".[$index].peers" | sed 's/\"//g' | awk '{print $1}')

        setGlobals $peer $org
        for ord in ${FABRIC_ORDERER_LIST}; do
            if [[ -z "$CORE_PEER_TLS_ENABLED" || "$CORE_PEER_TLS_ENABLED" == "false" ]]; then
                echo "peer channel create -o $ord:7050 -c $ch_name -f ./channel-artifacts/${ch_name}.tx >& ${EXECUTE_LOG}"
                peer channel create -o $ord:7050 -c $ch_name -f ./channel-artifacts/${ch_name}.tx >&${EXECUTE_LOG}
            else
                echo "peer channel create -o $ord:7050 -c $ch_name -f ./channel-artifacts/${ch_name}.tx --tls --cafile $ORDERER_CA >&${EXECUTE_LOG}"
                peer channel create -o $ord:7050 -c $ch_name -f ./channel-artifacts/${ch_name}.tx --tls --cafile $ORDERER_CA >&${EXECUTE_LOG}
            fi
            res=$?
            cat ${EXECUTE_LOG}
            verifyResult $res "Channel creation failed"
            echo "===================== Channel \"$ch_name\" created ===================== "
            echo
        done
    done
}

updateAnchorPeers() {
    for index in $(seq 0 $CHANNEL_SIZE); do
        ch_name=$(echo $CHANNEL_JSON | jq ".[$index].name" | sed 's/\"//g')
        orgs=$(echo $CHANNEL_JSON | jq ".[$index].orgs" | sed 's/\"//g')
        peer=$(echo $CHANNEL_JSON | jq ".[$index].peers" | sed 's/\"//g' | awk '{print $1}')

        for org in ${orgs}; do
            setGlobals $peer $org

            archorFile=${ch_name}_Org${org}-anchors.tx
            for ord in ${FABRIC_ORDERER_LIST}; do
                if [[ -z "$CORE_PEER_TLS_ENABLED" || "$CORE_PEER_TLS_ENABLED" == "false" ]]; then
                    echo "peer channel update -o $ord:7050 -c $ch_name -f ./channel-artifacts/${CORE_PEER_LOCALMSPID}anchors.tx >& ${EXECUTE_LOG}"
                    peer channel update -o $ord:7050 -c $ch_name -f ./channel-artifacts/${archorFile} >&${EXECUTE_LOG}
                else
                    echo "peer channel update -o $ord:7050 -c $ch_name -f ./channel-artifacts/${archorFile} --tls --cafile $ORDERER_CA >&${EXECUTE_LOG}"
                    peer channel update -o $ord:7050 -c $ch_name -f ./channel-artifacts/${archorFile} --tls --cafile $ORDERER_CA >&${EXECUTE_LOG}
                fi
                res=$?
                cat ${EXECUTE_LOG}
                verifyResult $res "Anchor peer update failed"
                echo "===================== Anchor peers updated for org \"$CORE_PEER_LOCALMSPID\" on channel \"$ch_name\" ===================== "
                sleep 5
                echo
            done
        done
    done
}

## Sometimes Join takes time hence RETRY atleast for 5 times
joinChannelWithRetry() {
    PEER=$1
    ORG=$2
    CH_NAME=$3
    setGlobals $PEER $ORG

    PEER_CONTAINER_NAME=peer${PEER}Org${ORG}
    peer channel join -b ${CH_NAME}.block >&${EXECUTE_LOG}
    res=$?
    cat ${EXECUTE_LOG}
    if [[ $res -ne 0 && $COUNTER -lt $MAX_RETRY ]]; then
        COUNTER=$(expr $COUNTER + 1)
        echo "${PEER_CONTAINER_NAME} failed to join the channel, Retry after 2 seconds"
        sleep 2
        joinChannelWithRetry ${PEER} ${ORG}
    else
        COUNTER=1
    fi
    verifyResult $res "After $MAX_RETRY attempts, ${PEER_CONTAINER_NAME} has failed to join channel \"$CH_NAME\" "
}

joinChannel() {
    sleep 5

    for index in $(seq 0 $CHANNEL_SIZE); do
        ch_name=$(echo $CHANNEL_JSON | jq ".[$index].name" | sed 's/\"//g')
        orgs=$(echo $CHANNEL_JSON | jq ".[$index].orgs" | sed 's/\"//g')
        peers=$(echo $CHANNEL_JSON | jq ".[$index].peers" | sed 's/\"//g')

        for org in ${orgs}; do
            for peer in ${peers}; do
                joinChannelWithRetry $peer $org $ch_name
                echo "===================== peer${peer}Org${org} joined channel \"$ch_name\" ===================== "
                sleep 2
                echo
            done
        done
    done
}

installChaincode() {
    CCNAME=$1
    CHANCODE=$2

    orgs=$(echo $ORG_PEER_JSON | jq ".orgs" | sed 's/\"//g')
    peers=$(echo $ORG_PEER_JSON | jq ".peers" | sed 's/\"//g')

    for org in ${orgs}; do
        for peer in ${peers}; do
            setGlobals $peer $org

            PEER_NAME=peer${peer}Org${org}
            echo "peer chaincode install -n ${CCNAME} -v ${VERSION} -p ${CHANCODE} >& ${EXECUTE_LOG}"
            peer chaincode install -n ${CCNAME} -v ${VERSION} -p ${CHANCODE} >&${EXECUTE_LOG}
            res=$?
            cat ${EXECUTE_LOG}
            verifyResult $res "Chaincode installation on remote ${PEER_NAME} has Failed"
            echo "===================== Chaincode is installed on ${PEER_NAME} ===================== "
            echo
        done
    done
}

instantiateChaincode() {
    CCNAME=$1
    INIT_ARGS=$2

    for ord in ${FABRIC_ORDERER_LIST}; do
        for index in $(seq 0 $CHANNEL_SIZE); do
            sleep 2

            ch_name=$(echo $CHANNEL_JSON | jq ".[$index].name" | sed 's/\"//g')
            org=$(echo $CHANNEL_JSON | jq ".[$index].orgs" | sed 's/\"//g' | awk '{print $1}')
            peer=$(echo $CHANNEL_JSON | jq ".[$index].peers" | sed 's/\"//g' | awk '{print $1}')

            echo "org: $org, channel name: $ch_name, peer: $peer"
            setGlobals $peer $org

            if [[ -z "$CORE_PEER_TLS_ENABLED" || "$CORE_PEER_TLS_ENABLED" == "false" ]]; then
                echo "peer chaincode instantiate -o $ord:7050 -C $ch_name -n ${CCNAME} -v ${VERSION} -c ${INIT_ARGS} >& ${EXECUTE_LOG}"
                peer chaincode instantiate -o $ord:7050 -C $ch_name -n ${CCNAME} -v ${VERSION} -c ${INIT_ARGS} >&${EXECUTE_LOG}
            else
                echo "peer chaincode instantiate -o $ord:7050 --tls --cafile $ORDERER_CA -C $ch_name -n ${CCNAME} -v ${VERSION} -c ${INIT_ARGS} >&${EXECUTE_LOG}"
                peer chaincode instantiate -o $ord:7050 --tls --cafile $ORDERER_CA -C $ch_name -n ${CCNAME} -v ${VERSION} -c ${INIT_ARGS} >&${EXECUTE_LOG}
            fi
            res=$?
            cat ${EXECUTE_LOG}
            verifyResult $res "Chaincode instantiation on peer${peer}Org${org} on channel \"$ch_name\" failed"
            echo "===================== Chaincode is instantiated on peer${peer}Org${org} on channel \"$ch_name\" ===================== "
            echo
        done
    done
}

## Check for orderering service availablility
echo "Check orderering service availability..."
checkOSNAvailability

if [[ ! -f "${CC_INSTALLED_FILE}" ]]; then
    ## Create channel
    echo "Creating channel..."
    createChannel

    ## Join all the peers to the channel
    echo "Having all peers join the channel..."
    joinChannel

    ## Set the anchor peers for each org in the channel
    echo "Updating anchor peers for orgs..."
    updateAnchorPeers

    ## Install chaincode on Peer0/Org1 and Peer0/Org2
    echo "Installing chaincode ..."
    installChaincode ${CHAINCODE_NAME} ${CC_INSTALL}

    displayInfo >${CC_INSTALLED_FILE}
fi

## Instantiate chaincode on Peer0/Org1 and Peer0/Org2
echo "Instantiating chaincode ..."
instantiateChaincode ${CHAINCODE_NAME} "${CHAINCODE_INIT_ARGS}"

echo
echo "===================== All GOOD, End-2-End execution completed ===================== "
echo

echo
echo " _____   _   _   ____            _____   ____    _____ "
echo "| ____| | \ | | |  _ \          | ____| |___ \  | ____|"
echo "|  _|   |  \| | | | | |  _____  |  _|     __) | |  _|  "
echo "| |___  | |\  | | |_| | |_____| | |___   / __/  | |___ "
echo "|_____| |_| \_| |____/          |_____| |_____| |_____|"
echo

rm -f ${EXECUTE_LOG}
exit 0
