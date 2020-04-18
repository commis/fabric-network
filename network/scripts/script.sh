#!/bin/bash

echo
echo " ____    _____      _      ____    _____ "
echo "/ ___|  |_   _|    / \    |  _ \  |_   _|"
echo "\___ \    | |     / _ \   | |_) |   | |  "
echo " ___) |   | |    / ___ \  |  _ <    | |  "
echo "|____/    |_|   /_/   \_\ |_| \_\   |_|  "
echo
echo "Build your first network (BYFN) end-to-end test"
echo
CHANNEL_NAME="$1"
DELAY="$2"
CC_SRC_LANGUAGE="$3"
TIMEOUT="$4"
VERBOSE="$5"
NO_CHAINCODE="$6"
: ${CHANNEL_NAME:="mychannel"}
: ${DELAY:="3"}
: ${CC_SRC_LANGUAGE:="go"}
: ${TIMEOUT:="10"}
: ${VERBOSE:="false"}
: ${NO_CHAINCODE:="false"}
CC_SRC_LANGUAGE=$(echo "$CC_SRC_LANGUAGE" | tr [:upper:] [:lower:])
COUNTER=1
MAX_RETRY=20
PACKAGE_ID=""

if [ "$CC_SRC_LANGUAGE" = "go" -o "$CC_SRC_LANGUAGE" = "golang" ]; then
    CC_RUNTIME_LANGUAGE=golang
    CC_SRC_PATH="github.com/chaincode/chaincode_token/go/"
elif [ "$CC_SRC_LANGUAGE" = "javascript" ]; then
    CC_RUNTIME_LANGUAGE=node # chaincode runtime language is node.js
    CC_SRC_PATH="/opt/gopath/src/github.com/hyperledger/fabric-samples/chaincode/abstore/javascript/"
elif [ "$CC_SRC_LANGUAGE" = "java" ]; then
    CC_RUNTIME_LANGUAGE=java
    CC_SRC_PATH="/opt/gopath/src/github.com/hyperledger/fabric-samples/chaincode/abstore/java/"
else
    echo The chaincode language ${CC_SRC_LANGUAGE} is not supported by this script
    echo Supported chaincode languages are: go, javascript, java
    exit 1
fi

echo "Channel name : "$CHANNEL_NAME

# import utils
. scripts/utils.sh

createChannel() {
    setGlobals 0 1

    if [ -z "$CORE_PEER_TLS_ENABLED" -o "$CORE_PEER_TLS_ENABLED" = "false" ]; then
        set -x
        peer channel create -o orderer.example.com:7050 -c $CHANNEL_NAME -f ./channel-artifacts/$CHANNEL_NAME.tx >&log.txt
        res=$?
        set +x
    else
        set -x
        peer channel create -o orderer.example.com:7050 -c $CHANNEL_NAME -f ./channel-artifacts/$CHANNEL_NAME.tx --tls $CORE_PEER_TLS_ENABLED --cafile $ORDERER_CA >&log.txt
        res=$?
        set +x
    fi
    cat log.txt
    verifyResult $res "Channel creation failed"
    echo "===================== Channel '$CHANNEL_NAME' created ===================== "
    echo
}

joinChannel() {
    for org in 1 2; do
        for peer in 0 1; do
            joinChannelWithRetry $peer $org
            echo "===================== peer${peer}.org${org} joined channel '$CHANNEL_NAME' ===================== "
            sleep $DELAY
            echo
        done
    done
}

## Create channel
echo "Creating channel..."
createChannel

## Join all the peers to the channel
echo "Having all peers join the channel..."
joinChannel

## Set the anchor peers for each org in the channel
echo "Updating anchor peers for org1..."
updateAnchorPeers 0 1
echo "Updating anchor peers for org2..."
updateAnchorPeers 0 2

if [ "${NO_CHAINCODE}" != "true" ]; then
    ## at first we package the chaincode
    packageChaincode 1 0 1

    ## Install chaincode on peers
    for org in 1 2; do
        for peer in 0 1; do
            echo "Installing chaincode on peer${peer}.org${org}..."
            installChaincode ${peer} ${org}
        done
    done

    ## query whether the chaincode is installed
    queryInstalled 0 1

    ## approve the definition for org1 and org2
    approveForMyOrg 1 0 1
    approveForMyOrg 1 0 2

    ## now that we know for sure both orgs have approved, commit the definition
    commitChaincodeDefinition 1 0 1 0 2

    ## query on both orgs to see that the definition committed successfully
    queryCommitted 1 0 1
    queryCommitted 1 0 2

    ## invoke init
    chaincodeInvoke 1 0 1 0 2

    ## Query chaincode on peer0.org1
    #echo "Querying chaincode on peer0.org1..."
    #chaincodeQuery 0 1 100

    ## Invoke chaincode on peer0.org1 and peer0.org2
    #echo "Sending invoke transaction on peer0.org1 peer0.org2..."
    #chaincodeInvoke 0 0 1 0 2

    ## Query chaincode on peer0.org1
    #echo "Querying chaincode on peer0.org1..."
    #chaincodeQuery 0 1 90

    ## Install chaincode on peer1.org2
    #echo "Installing chaincode on peer1.org2..."
    #installChaincode 1 2

    ## Query on chaincode on peer1.org2, check if the result is 90
    #echo "Querying chaincode on peer1.org2..."
    #chaincodeQuery 1 2 90

fi

echo
echo "========= All GOOD, BYFN execution completed =========== "
echo

echo
echo " _____   _   _   ____   "
echo "| ____| | \ | | |  _ \  "
echo "|  _|   |  \| | | | | | "
echo "| |___  | |\  | | |_| | "
echo "|_____| |_| \_| |____/  "
echo

exit 0
