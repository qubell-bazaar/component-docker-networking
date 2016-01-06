#!/bin/bash
pkg="etcd-cluster"
etcd_peers_file_path="/etc/etcd/etcd.conf"
etcd_peer_urls=`echo ${ETCD_PEER_URLS}|sed -e 's/,/ /g'`

# Allow default client/server ports to be changed if necessary
client_port=${ETCD_CLIENT_PORT:-2379}
server_port=${ETCD_SERVER_PORT:-2380}

# ETCD API https://coreos.com/etcd/docs/2.0.11/other_apis.html
add_ok=201
already_added=409
delete_ok=204

ec2_instance_ip=$(hostname -i)
if [[ ! $ec2_instance_ip ]]; then
    echo "$pkg: failed to get instance IP address"
    exit 3
fi
etcd_client_scheme=${ETCD_CLIENT_SCHEME:-http}
echo "client_client_scheme=$etcd_client_scheme"
etcd_peer_scheme=${ETCD_PEER_SCHEME:-http}
echo "peer_peer_scheme=$etcd_peer_scheme"

if [[ ! $etcd_peer_urls ]]; then
    echo "$pkg: unable to find members of role"
    exit 5
fi

function clean_bad_members {
    # eject bad members from cluster
    echo "Cleanup bad nodes" 
    peer_regexp=$(echo "${etcd_peer_urls[@]}"| tr ' ' '\n' | sed 's/^.*https\{0,1\}:\/\/\([0-9.]*\):[0-9]*.*$/contains(\\"\/\/\1:\\")/' | xargs | sed 's/  */ or /g')
    if [[ ! $peer_regexp ]]; then
        echo "$pkg: failed to create peer regular expression"
        exit 6
    fi

    echo "peer_regexp=$peer_regexp"
    bad_peer=$(echo "$etcd_members" | jq --raw-output ".[] | map(select(.peerURLs[] | $peer_regexp | not )) | .[].id")
    echo "bad_peer=$bad_peer"

    if [[ $bad_peer ]]; then
        for bp in $bad_peer; do
            echo "removing bad peer $bp"
            status=$(curl $ETCD_CURLOPTS -f -s -w %{http_code} "$etcd_good_member_url/v2/members/$bp" -XDELETE)
            if [[ $status != $delete_ok ]]; then
                echo "$pkg: ERROR: failed to remove bad peer: $bad_peer, return code $status."
                exit 7
            fi
        done
    fi
}

function restart_etcd {
    systemctl daemon-reload
    systemctl enable etcd.service
    systemctl stop etcd.service
    sleep 10
    systemctl start etcd.service
}

echo "etcd_peer_urls=$etcd_peer_urls"

etcd_existing_peer_urls=
etcd_existing_peer_names=
etcd_good_member_url=

for url in ${etcd_peer_urls}; do
    echo "processing url=$url"

    etcd_members=$(curl $ETCD_CURLOPTS -f -s $url/v2/members)

    if [[ $? == 0 && $etcd_members ]]; then
        etcd_good_member_url="$url"
		echo "etcd_members=$etcd_members"
        etcd_existing_peer_urls=$(echo "$etcd_members" | jq --raw-output .[][].peerURLs[0])
		etcd_existing_peer_names=$(echo "$etcd_members" | jq --raw-output .[][].name)
	break
    fi
done

echo "etcd_good_member_url=$etcd_good_member_url"
echo "etcd_existing_peer_urls=$etcd_existing_peer_urls"
echo "etcd_existing_peer_names=$etcd_existing_peer_names"

if [[ $etcd_existing_peer_urls && $etcd_existing_peer_names != *"$ec2_instance_ip"* ]]; then
    echo "joining existing cluster"
    echo "Cleanup bad nodes"
    clean_bad_members
    # We add ourselves as a member to the cluster
        etcd_initial_cluster=$(curl $ETCD_CURLOPTS -s -f "$etcd_good_member_url/v2/members" | jq --raw-output '.[] | map(.name + "=" + .peerURLs[0]) | .[]' | xargs | sed 's/  */,/g')$(echo ",$ec2_instance_ip=${etcd_peer_scheme}://${ec2_instance_ip}:$server_port")
        echo "etcd_initial_cluster=$etcd_initial_cluster"
        if [[ ! $etcd_initial_cluster ]]; then
            echo "$pkg: docker command to get etcd peers failed"
            exit 8
        fi

        # join an existing cluster
        echo "adding instance ID $ec2_instance_ip with IP $ec2_instance_ip"
        status=$(curl $ETCD_CURLOPTS -f -s -w %{http_code} -o /dev/null -XPOST "$etcd_good_member_url/v2/members" -H "Content-Type: application/json" -d "{\"peerURLs\": [\"$etcd_peer_scheme://$ec2_instance_ip:$server_port\"], \"name\": \"$ec2_instance_ip\"}")
        if [[ $status != $add_ok && $status != $already_added ]]; then
            echo "$pkg: unable to add $ec2_instance_ip to the cluster: return code $status."
            exit 9
        fi

    cat > "$etcd_peers_file_path" <<EOF
ETCD_INITIAL_CLUSTER_STATE=existing
ETCD_NAME=$ec2_instance_ip
ETCD_INITIAL_CLUSTER="$etcd_initial_cluster"
ETCD_DATA_DIR="/var/lib/etcd/default.etcd"
ETCD_LISTEN_PEER_URLS="http://`hostname -i`:$server_port"
ETCD_LISTEN_CLIENT_URLS="http://`hostname -i`:$client_port,http://localhost:$client_port"
ETCD_INITIAL_ADVERTISE_PEER_URLS="http://`hostname -i`:$server_port"
EOF
restart_etcd
# otherwise I was already listed as a member so assume that this is a new cluster
else
  echo "Creating new cluster..."
  etcd_pid=$(pgrep etcd)
  etct_member_count=$(echo `curl $ETCD_CURLOPTS -f -s http://localhost:$client_port/v2/members` |jq -r '.[] | length')
  if [[ $etcd_pid && $etct_member_count > 1  ]]; then
    echo "Cluster already configured on tis node"
    clean_bad_members
    exit 0
  else

  # create a new cluster
    etcd_initial_cluster="${ETCD_CLUSTER}"
    echo "etcd_initial_cluster=$etcd_initial_cluster"
    if [[ ! $etcd_initial_cluster ]]; then
        echo "$pkg: unable to get peers from role"
        exit 10
    fi

    cat > "$etcd_peers_file_path" <<EOF
ETCD_INITIAL_CLUSTER_STATE=new
ETCD_NAME=$ec2_instance_ip
ETCD_DATA_DIR="/var/lib/etcd/default.etcd"
ETCD_LISTEN_PEER_URLS="http://`hostname -i`:$server_port"
ETCD_LISTEN_CLIENT_URLS="http://`hostname -i`:$client_port,http://localhost:$client_port"
ETCD_INITIAL_ADVERTISE_PEER_URLS="http://`hostname -i`:$server_port"
ETCD_INITIAL_CLUSTER="$etcd_initial_cluster"
EOF
  restart_etcd  
  fi
fi
exit 
