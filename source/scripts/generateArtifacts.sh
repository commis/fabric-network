#!/usr/bin/bash

set -e

# all global environment parameter
SOURCE_ROOT=$(cd `dirname $(readlink -f "$0")`/.. && pwd)
COMPOSE_FILE=${SOURCE_ROOT}/docker-compose-cli.yaml
OS_ARCH=$(echo "$(uname -s|tr '[:upper:]' '[:lower:]'|sed 's/mingw64_nt.*/windows/')-$(uname -m | sed 's/x86_64/amd64/g')" | awk '{print tolower($0)}')

[[ "$(uname -s | grep Darwin)" == "Darwin" ]] && OPTS="-it" || OPTS="-i"
export FABRIC_CFG_PATH=${SOURCE_ROOT}

function getToolsFullPath() {
    echo "${SOURCE_ROOT}/tools/${OS_ARCH}/$1"
}

function getPeerOrgDomain() {
    domain=$(cat ${SOURCE_ROOT}/scripts/.env |grep "^PEER_DOMAIN_${1}"|awk -F'=' '{print $2}')
    echo $domain
}

## Using docker-compose template replace private key file names with constants
function replacePrivateKey () {
    current=`pwd`
    if [[ -f "${COMPOSE_FILE}" ]]; then
        CHANNEL_JSON=$(cat ${SOURCE_ROOT}/scripts/.env |grep '^CHANNEL_SET'|awk -F'=' '{print $2}')
        CHANNEL_SIZE=$(echo ${CHANNEL_JSON} |jq 'length-1')
        for index in $(seq 0 $CHANNEL_SIZE); do
            id=$(echo $CHANNEL_JSON |jq ".[$index].id")
            org_domain=$(getPeerOrgDomain ${id})
            cd ${SOURCE_ROOT}/crypto-config/peerOrganizations/${org_domain}/ca/
            PRIV_KEY=$(ls *_sk)
            cd $current
            sed $OPTS "s/CA${id}_PRIVATE_KEY/${PRIV_KEY}/g" ${COMPOSE_FILE}
        done
    fi
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

	current=`pwd`
	IDEMIXMATDIR=${SOURCE_ROOT}/crypto-config/idemix
	mkdir -p $IDEMIXMATDIR
	cd $IDEMIXMATDIR

	# Generate the idemix issuer keys
	$IDEMIXGEN ca-keygen

	# Generate the idemix signer keys
	$IDEMIXGEN signerconfig -u OU1 -e OU1 -r 1

	cd ${current}
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

    CHANNEL_JSON=$(cat ${SOURCE_ROOT}/scripts/.env |grep '^CHANNEL_SET'|awk -F'=' '{print $2}')
    CHANNEL_SIZE=$(echo $CHANNEL_JSON |jq 'length-1')

    for index in $(seq 0 $CHANNEL_SIZE); do
        profile_ch=$(echo $CHANNEL_JSON |jq ".[$index].cfg"|sed 's/\"//g')
        ch_name=$(echo $CHANNEL_JSON |jq ".[$index].name"|sed 's/\"//g')

        echo
        echo "#################################################################"
        echo "### Generating channel configuration transaction 'channel.tx' ###"
        echo "#################################################################"
        $CONFIGTXGEN -profile $profile_ch -outputCreateChannelTx ${SOURCE_ROOT}/channel-artifacts/${ch_name}.tx -channelID $ch_name

        orgs=$(echo $CHANNEL_JSON |jq ".[$index].orgs"|sed 's/\"//g')
        for org in ${orgs}; do
            archorFile=${ch_name}_Org${org}-anchors.tx
            orgMsp=$(cat ${SOURCE_ROOT}/scripts/.env |grep "^PEER_MSPID_${org}"|awk -F'=' '{print $2}')
            echo
            echo "#################################################################"
            echo "#######    Generating anchor peer update for OrgMSP   ##########"
            echo "#################################################################"
            $CONFIGTXGEN -profile $profile_ch -outputAnchorPeersUpdate ${SOURCE_ROOT}/channel-artifacts/${archorFile} -channelID $ch_name -asOrg $orgMsp
            echo
        done
	done
}

current=`pwd`
echo $current
cd ${SOURCE_ROOT}

generateCerts
generateIdemixMaterial
replacePrivateKey
generateChannelArtifacts
cd ${current}
