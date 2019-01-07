#!/usr/bin/bash

set -e

# all global environment parameter
SOURCE_ROOT=$(cd `dirname $(readlink -f "$0")`/.. && pwd)
OS_ARCH=$(echo "$(uname -s|tr '[:upper:]' '[:lower:]'|sed 's/mingw64_nt.*/windows/')-$(uname -m | sed 's/x86_64/amd64/g')" | awk '{print tolower($0)}')
echo ${OS_ARCH}

export FABRIC_CFG_PATH=${SOURCE_ROOT}

CH_NAME=$1
: ${CH_NAME:="${CHANNEL_NAME}"}
echo $CH_NAME

function getToolsFullPath() {
    echo "${SOURCE_ROOT}/tools/${OS_ARCH}/$1"
}

## Using docker-compose template replace private key file names with constants
function replacePrivateKey () {
    [[ "$(uname -s | grep Darwin)" == "Darwin" ]] && OPTS="-it" || OPTS="-i"
    
    CURRENT_DIR=$PWD
    cd ${SOURCE_ROOT}/crypto-config/peerOrganizations/yzhorg.net/ca/
    PRIV_KEY=$(ls *_sk)
    cd $CURRENT_DIR
    sed $OPTS "s/CA1_PRIVATE_KEY/${PRIV_KEY}/g" ${SOURCE_ROOT}/docker-compose-e2e.yaml

#    cd ${SOURCE_ROOT}/crypto-config/peerOrganizations/org2.yzhorg.net/ca/
#    PRIV_KEY=$(ls *_sk)
#    cd $CURRENT_DIR
#    sed $OPTS "s/CA2_PRIVATE_KEY/${PRIV_KEY}/g" ${SOURCE_ROOT}/docker-compose-e2e.yaml
}

## Generates Org certs using cryptogen tool
function generateCerts () {
    CRYPTOGEN=$(getToolsFullPath cryptogen)
    
    if [ -f "$CRYPTOGEN" ]; then
        echo "Using cryptogen -> $CRYPTOGEN"
    fi

    echo
	echo "##########################################################"
	echo "##### Generate certificates using cryptogen tool #########"
	echo "##########################################################"
	${CRYPTOGEN} generate --config=${SOURCE_ROOT}/crypto-config.yaml
	echo

	if [[ -d "${SOURCE_ROOT}/scripts/crypto-config" ]]; then
        sudo mv ${SOURCE_ROOT}/scripts/crypto-config ${SOURCE_ROOT}/
    fi
}

function generateIdemixMaterial() {
    IDEMIXGEN=$(getToolsFullPath idemixgen)

    if [[ -f "$IDEMIXGEN" ]]; then
        echo "Using idemixgen -> $IDEMIXGEN"
    fi

	echo
	echo "####################################################################"
	echo "##### Generate idemix crypto material using idemixgen tool #########"
	echo "####################################################################"

	CURDIR=`pwd`
	IDEMIXMATDIR=${SOURCE_ROOT}/crypto-config/idemix
	mkdir -p $IDEMIXMATDIR
	cd $IDEMIXMATDIR

	# Generate the idemix issuer keys
	$IDEMIXGEN ca-keygen

	# Generate the idemix signer keys
	$IDEMIXGEN signerconfig -u OU1 -e OU1 -r 1

	cd $CURDIR
}

## Generate orderer genesis block , channel configuration transaction and anchor peer update transactions
function generateChannelArtifacts() {
    CONFIGTXGEN=$(getToolsFullPath configtxgen)
    
    if [ -f "$CONFIGTXGEN" ]; then
        echo "Using configtxgen -> $CONFIGTXGEN"
    fi

    echo "##########################################################"
	echo "#########  Generating Orderer Genesis block ##############"
	echo "##########################################################"
	# Note: For some unknown reason (at least for now) the block file can't be
	# named orderer.genesis.block or the orderer will fail to launch!
	$CONFIGTXGEN -profile OrdererGenesis -channelID e2e-orderer-syschan -outputBlock ${SOURCE_ROOT}/channel-artifacts/genesis.block

    echo
	echo "#################################################################"
	echo "### Generating channel configuration transaction 'channel.tx' ###"
	echo "#################################################################"
	$CONFIGTXGEN -profile YzhChannel -outputCreateChannelTx ${SOURCE_ROOT}/channel-artifacts/channel.tx -channelID $CH_NAME

    echo
	echo "#################################################################"
	echo "#######    Generating anchor peer update for Org1MSP   ##########"
	echo "#################################################################"
	$CONFIGTXGEN -profile YzhChannel -outputAnchorPeersUpdate ${SOURCE_ROOT}/channel-artifacts/YzhMSPanchors.tx -channelID $CH_NAME -asOrg YzhMSP

#   echo
#	echo "#################################################################"
#	echo "#######    Generating anchor peer update for Org2MSP   ##########"
#	echo "#################################################################"
#	$CONFIGTXGEN -profile TwoOrgsChannel -outputAnchorPeersUpdate ${SOURCE_ROOT}/channel-artifacts/Org2MSPanchors.tx -channelID $CH_NAME -asOrg Org2MSP
	echo
}

generateCerts
generateIdemixMaterial
replacePrivateKey
generateChannelArtifacts
