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
ORD_DOMAIN=$(cat ${ROOT_DIR}/.env |grep 'ORDERER_DOMAIN' |awk -F'=' '{print $2}')
PER_DOMAIN=$(cat ${ROOT_DIR}/.env |grep 'PEER_DOMAIN' |awk -F'=' '{print $2}')

CH_NAME="$1"
VERSION="$2"
CC_INSTALL="$3"
: ${CH_NAME:="${CHANNEL_NAME}"}
: ${VERSION:="${VERSION}"}
: ${TIMEOUT:="600000"}
COUNTER=1
MAX_RETRY=5
ORDERER_SYSCHAN_ID=e2e-orderer-syschan

if [[ -z "$CC_INSTALL" ]]; then
    echo "Please input install chaincode path relation of GOPATH"
    exit 1
fi

CC_INSTALLED_FILE=/var/hyperledger/chaincode
echo "Channel name : $CH_NAME"

ORDERER_CA=/cli/crypto/ordererOrganizations/${ORD_DOMAIN}/orderers/orderer.${ORD_DOMAIN}/msp/tlscacerts/tlsca.${ORD_DOMAIN}-cert.pem
if [[ -z "$CORE_PEER_TLS_ENABLED" || "$CORE_PEER_TLS_ENABLED" = "true" ]]; then
    PEER_OPTS="--tls ${CORE_PEER_TLS_ENABLED} --cafile $ORDERER_CA"
fi

displayInfo() {
    echo "channel: ${CH_NAME}"
    echo "chaincode: ${CHAINCODE_NAME}"
    echo "version: ${VERSION}"
}

verifyResult () {
    if [[ $1 -ne 0 ]] ; then
        echo "!!!!!!!!!!!!!!! "$2" !!!!!!!!!!!!!!!!"
        echo "================== ERROR !!! FAILED to execute End-2-End Scenario =================="
        echo
        exit 1
    fi
}

setGlobals () {
    PEER=$1
	ORG=$2

    PEER_DOMAIN=$(cat ${ROOT_DIR}/.env |grep 'PEER_DOMAIN' |awk -F'=' '{print $2}')
    CORE_PEER_LOCALMSPID=$(cat ${ROOT_DIR}/.env |grep 'PEER_MSPID' |awk -F'=' '{print $2}')

    CLI_SERVER_REMOTE_CFG=/cli/crypto/peerOrganizations/${PEER_DOMAIN}
    # it is must user first peer0 of org
    CORE_PEER_TLS_ROOTCERT_FILE=${CLI_SERVER_REMOTE_CFG}/peers/peer0.${PEER_DOMAIN}/tls/ca.crt
    CORE_PEER_MSPCONFIGPATH=${CLI_SERVER_REMOTE_CFG}/users/Admin@${PEER_DOMAIN}/msp

    CORE_PEER_ADDRESS=peer${1}:7051

    env |grep CORE
}

checkOSNAvailability() {
    #Use orderer's MSP for fetching system channel config block
    ORD_DOMAIN=$(cat ${ROOT_DIR}/.env |grep 'ORDERER_DOMAIN' |awk -F'=' '{print $2}')
    CORE_PEER_LOCALMSPID=$(cat ${ROOT_DIR}/.env |grep 'ORDERER_MSPID' |awk -F'=' '{print $2}')

    CORE_PEER_TLS_ROOTCERT_FILE=$ORDERER_CA
    CORE_PEER_MSPCONFIGPATH=/cli/crypto/ordererOrganizations/${ORD_DOMAIN}/orderers/orderer.${ORD_DOMAIN}/msp

    local rc=1
    local starttime=$(date +%s)
    
    # continue to poll
    # we either get a successful response, or reach TIMEOUT
    while test "$(($(date +%s)-starttime))" -lt "$TIMEOUT" -a $rc -ne 0
    do
        for ord in ${FABRIC_ORDERER_LIST}; do
            sleep 3
            echo "Attempting to fetch system channel '$ORDERER_SYSCHAN_ID' ${ord} ...$(($(date +%s)-starttime)) secs"
            if [[ -z "$CORE_PEER_TLS_ENABLED" || "$CORE_PEER_TLS_ENABLED" = "false" ]]; then
                peer channel fetch 0 -o $ord:7050 -c "$ORDERER_SYSCHAN_ID" >& ${EXECUTE_LOG}
            else
                peer channel fetch 0 0_block.pb -o $ord:7050 -c "$ORDERER_SYSCHAN_ID" --tls --cafile $ORDERER_CA >& ${EXECUTE_LOG}
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
    ch=$(echo $FABRIC_PEERS_LIST |awk '{print $1}')
    setGlobals $ch $ORG

    for ord in ${FABRIC_ORDERER_LIST}; do
        if [[ -z "$CORE_PEER_TLS_ENABLED" || "$CORE_PEER_TLS_ENABLED" = "false" ]]; then
            peer channel create -o $ord:7050 -c $CH_NAME -f ./channel-artifacts/channel.tx >& ${EXECUTE_LOG}
        else
            peer channel create -o $ord:7050 -c $CH_NAME -f ./channel-artifacts/channel.tx --tls --cafile $ORDERER_CA >& ${EXECUTE_LOG}
        fi
        res=$?
        cat ${EXECUTE_LOG}
        verifyResult $res "Channel creation failed"
        echo "===================== Channel \"$CH_NAME\" created ===================== "
        echo
    done
}

updateAnchorPeers() {
    PEER=$1
    ORG=1
    setGlobals $PEER $ORG

    for ord in ${FABRIC_ORDERER_LIST}; do
        if [[ -z "$CORE_PEER_TLS_ENABLED" || "$CORE_PEER_TLS_ENABLED" = "false" ]]; then
            peer channel update -o $ord:7050 -c $CH_NAME -f ./channel-artifacts/${CORE_PEER_LOCALMSPID}anchors.tx >& ${EXECUTE_LOG}
        else
            peer channel update -o $ord:7050 -c $CH_NAME -f ./channel-artifacts/${CORE_PEER_LOCALMSPID}anchors.tx --tls --cafile $ORDERER_CA >& ${EXECUTE_LOG}
        fi
        res=$?
        cat ${EXECUTE_LOG}
        verifyResult $res "Anchor peer update failed"
        echo "===================== Anchor peers updated for org \"$CORE_PEER_LOCALMSPID\" on channel \"$CH_NAME\" ===================== "
        sleep 5
        echo
    done
}

## Sometimes Join takes time hence RETRY atleast for 5 times
joinChannelWithRetry () {
    PEER=$1
	ORG=$2
	setGlobals $PEER $ORG

	peer channel join -b ${CH_NAME}.block  >& ${EXECUTE_LOG}
	res=$?
	cat ${EXECUTE_LOG}
	if [[ $res -ne 0 && $COUNTER -lt $MAX_RETRY ]]; then
		COUNTER=`expr $COUNTER + 1`
		echo "peer${PEER}.org${ORG} failed to join the channel, Retry after 2 seconds"
		sleep 2
		joinChannelWithRetry $1 $ORG
	else
		COUNTER=1
	fi
	verifyResult $res "After $MAX_RETRY attempts, ${PEER}.org${ORG} has failed to join channel \"$CH_NAME\" "
}

joinChannel () {
    sleep 15
    ORG=1

    for ord in ${FABRIC_ORDERER_LIST}; do
        for ch in ${FABRIC_PEERS_LIST}; do
            joinChannelWithRetry $ch $ORG
            echo "===================== peer${ch}.org${org} joined channel \"$CH_NAME\" ===================== "
            sleep 2
            echo
        done
    done
}

installChaincode () {
    CCNAME=$1
    CHANCODE=$2
    ORG=1

    for ch in ${FABRIC_PEERS_LIST}; do
        setGlobals $ch $ORG
        echo "peer chaincode install -n ${CCNAME} -v ${VERSION} -p ${CHANCODE} >& ${EXECUTE_LOG}"
        peer chaincode install -n ${CCNAME} -v ${VERSION} -p ${CHANCODE} >& ${EXECUTE_LOG}
        res=$?
        cat ${EXECUTE_LOG}
        verifyResult $res "Chaincode installation on remote peer${ch}.org${ORG} has Failed"
        echo "===================== Chaincode is installed on peer${ch}.org${ORG} ===================== "
        echo
    done
}

instantiateChaincode () {
    sleep 10
    CCNAME=$1
    INIT_ARGS=$2
    ORG=1

    for ord in ${FABRIC_ORDERER_LIST}; do
        for ch in ${FABRIC_PEERS_LIST}; do
            setGlobals $ch $ORG
            if [[ -z "$CORE_PEER_TLS_ENABLED" || "$CORE_PEER_TLS_ENABLED" = "false" ]]; then
                peer chaincode instantiate -o $ord:7050 -C $CH_NAME -n ${CCNAME} -v ${VERSION} -c ${INIT_ARGS} >& ${EXECUTE_LOG}
            else
                peer chaincode instantiate -o $ord:7050 --tls --cafile $ORDERER_CA -C $CH_NAME -n ${CCNAME} -v ${VERSION} -c ${INIT_ARGS} >& ${EXECUTE_LOG}
            fi
            res=$?
            cat ${EXECUTE_LOG}
            verifyResult $res "Chaincode instantiation on peer${ch}.org${ORG} on channel \"$CH_NAME\" failed"
            echo "===================== Chaincode is instantiated on peer${ch}.org${ORG} on channel \"$CH_NAME\" ===================== "
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
    echo "Updating anchor peers for org1..."
    updateAnchorPeers 0

    ## Install chaincode on Peer0/Org1 and Peer0/Org2
    echo "Installing chaincode ..."
    installChaincode ${CHAINCODE_NAME} ${CC_INSTALL}

    displayInfo > ${CC_INSTALLED_FILE}
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
