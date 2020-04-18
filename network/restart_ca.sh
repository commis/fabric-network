#!/bin/bash

function getPrivateKeyFile() {
    org=$1
    dir=$2
    cd crypto-config/peerOrganizations/${org}.example.com/${dir} || exit 1
    if [ -f priv_sk ]; then
        openssl x509 -in $(ls *.pem) -noout -text >pem.txt
        line=$(sed -n '/X509v3 Subject Key Identifier/=' pem.txt)
        data=$(sed -n "$(($line + 1))p" pem.txt | sed 's/[: ]//g' | tr 'A-Z' 'a-z')
        mv priv_sk ${data}_sk
        rm -f pem.txt
    fi
    ls *_sk
}

export BYFN_CA1_PRIVATE_KEY=$(getPrivateKeyFile org1 ca)
export BYFN_CA1_TLS_PRIVATE_KEY=$(getPrivateKeyFile org1 tlsca)
export BYFN_CA2_PRIVATE_KEY=$(getPrivateKeyFile org2 ca)
export BYFN_CA2_TLS_PRIVATE_KEY=$(getPrivateKeyFile org2 tlsca)

docker ps -a | grep ca.org | awk '{print $1}' | xargs -ti docker rm -f {}
#docker-compose -f docker-compose-ca.yaml up -d 2>&1
