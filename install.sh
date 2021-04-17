#!/usr/bin/env bash

set -e

srcdir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

function installCouchbaseServerMacOS {
    applicationsDir="/Applications"
    couchbaseServerVersion=6.6.0
    couchbaseServerDMG="couchbase-server-community_$couchbaseServerVersion-macos_x86_64.dmg"
    couchbaseServerUrl="https://packages.couchbase.com/releases/$couchbaseServerVersion/$couchbaseServerDMG"
    couchbaseServerAppName="Couchbase Server.app"
    couchbaseServerDMGMountPoint="/Volumes/Couchbase Installer "
    couchbaseServerApp="$applicationsDir/$couchbaseServerAppName"
    couchbaseServerAppBin="$couchbaseServerApp/Contents/Resources/couchbase-core/bin"

    echo "::group::Install Couchbase Server"

    curl "$couchbaseServerUrl" -o "$couchbaseServerDMG"
    sudo hdiutil attach "$couchbaseServerDMG"
    cp -R "$couchbaseServerDMGMountPoint/$couchbaseServerAppName" "$applicationsDir"
    sudo hdiutil detach "$couchbaseServerDMGMountPoint"
    rm "$couchbaseServerDMG"

    sudo xattr -d -r com.apple.quarantine "$couchbaseServerApp"
    open "$couchbaseServerApp"

    echo "$couchbaseServerAppBin" >>$GITHUB_PATH
    PATH="$couchbaseServerAppBin:$PATH"

    echo "127.0.0.1 couchbase" | sudo tee -a /etc/hosts

    echo "::endgroup::"
}

function waitForCouchbaseServer {
    echo "::group::Wait for Couchbase Server"

    while ! curl --silent -o /dev/null localhost:8091; do
        echo "Waiting for Couchbase Server to become available"
        sleep 5
    done

    echo "::endgroup::"
}

function prepareCouchbaseServer {
    serverAddress=couchbase
    clusterUsername=Admin
    clusterPassword=password

    echo "::group::Prepare Couchbase Server"

    # Create a one node cluster
    couchbase-cli cluster-init \
        -c "$serverAddress" \
        --cluster-username "$clusterUsername" \
        --cluster-password "$clusterPassword" \
        --services data,index,query \
        --cluster-ramsize 256 \
        --cluster-index-ramsize 256

    # Create the default bucket
    couchbase-cli bucket-create \
        -c "$serverAddress" \
        -u "$clusterUsername" \
        -p "$clusterPassword" \
        --bucket default \
        --bucket-type couchbase \
        --bucket-ramsize 100

    # Create the Sync Gateway RBAC user
    couchbase-cli user-manage \
        -c "$serverAddress" \
        -u "$clusterUsername" \
        -p "$clusterPassword" \
        --set \
        --auth-domain local \
        --rbac-name sync-gateway \
        --rbac-username sync-gateway \
        --rbac-password password \
        --roles admin

    echo "::endgroup::"
}

function installSyncGatewayMacOS {
    optDir="/opt"
    syncGatewayVersion=2.8.2
    syncGatewayZip="couchbase-sync-gateway-community_${syncGatewayVersion}_x86_64.zip"
    syncGatewayUrl="https://packages.couchbase.com/releases/couchbase-sync-gateway/$syncGatewayVersion/$syncGatewayZip"
    syncGatewayInstallDir="$optDir/couchbase-sync-gateway"
    syncGatewayUser="sync_gateway"
    syncGatewayConfig="$srcdir/sync-gateway-config.json"

    echo "::group::Install Sync Gateway"

    curl "$syncGatewayUrl" -o "$syncGatewayZip"
    sudo unzip "$syncGatewayZip" -d "$optDir"
    rm "$syncGatewayZip"

    sudo sysadminctl -addUser "$syncGatewayUser"
    sudo dseditgroup -o create "$syncGatewayUser"
    sudo dseditgroup -o edit -a "$syncGatewayUser" -t user "$syncGatewayUser"

    cd "$syncGatewayInstallDir/service"
    sudo ./sync_gateway_service_install.sh --cfgpath="$syncGatewayConfig"

    echo "::endgroup::"
}

function waitForSyncGateway {
    echo "::group::Wait for Sync Gateway"
    while ! curl --silent -o /dev/null localhost:4984; do
        echo "Waiting for Couchbase Sync Gateway to become available"
        sleep 5
    done
    echo "::endgroup::"
}

installCouchbaseServerMacOS
waitForCouchbaseServer
prepareCouchbaseServer
installSyncGatewayMacOS
waitForSyncGateway
