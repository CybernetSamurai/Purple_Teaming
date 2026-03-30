new_bridge () {
	sudo ip link add br0 type bridge
	sudo ip link set dev br0 up
}

new_netns () {
	local NAME=$1
	local IP=$2
	local NETNS=ci690-${NAME}

	sudo ip netns add ${NETNS}
	sudo ip link add dev veth-${NAME} type veth peer name veth0 netns ${NETNS}
	sudo ip link set dev veth-${NAME} up
	sudo ip netns exec ${NETNS} ip link set dev lo up
	sudo ip netns exec ${NETNS} ip link set dev veth0 up
	
	# add ip if supplied
	[ -n "${IP}" ] && sudo ip netns exec ${NETNS} ip address add ${IP} dev veth0
}

add_tagged_interface () {
	local NAME=$1
	local VLAN=$2
	local IP=$3
	local GW=$4
	local NETNS=ci690-${NAME}

	sudo ip netns exec ${NETNS} ip link add link veth0 name veth0.${VLAN} type vlan id ${VLAN}
	sudo ip netns exec ${NETNS} ip link set dev veth0.${VLAN} up
	sudo ip netns exec ${NETNS} ip address flush dev veth0

	# add ip if supplied
	[ -n "${IP}" ] && sudo ip netns exec ${NETNS} ip address add ${IP} dev veth0.${VLAN}
	[ -n "${GW}" ] && sudo ip netns exec ${NETNS} ip route add default via ${GW} dev veth0.${VLAN}
}

kill_net () {
	# delete net namespaces and veth links
	for NETNS in $(sudo ip netns list | grep "ci690-" | awk '{print $1}'); do
		[ -n "${NETNS}" ] || continue
		local NAME=${NETNS#ci690-}
		sudo ip link delete veth-${NAME}
		sudo ip netns delete ${NETNS}
	done

	# kill bridge if exists
	if ip link show dev br0 > /dev/null 2>&1; then
		sudo ip link delete br0
	fi
}

new_cluster () {
	local BASE_NAME=$1
	local COUNT=$2
	new_bridge

	for i in $(seq 1 $COUNT); do
		local NAME=${BASE_NAME}${i}
		local NETNS=ci690-${NAME}
		local VLAN=$((100 + i))
		local IP=$(random_ip)/24
		local GW=${IP%.*}.254

		new_netns ${NAME}
		sudo ip link set veth-${NAME} master br0

		# if generated bad ip/gw, try again
		until add_tagged_interface ${NAME} ${VLAN} ${IP} ${GW}; do
			sudo ip netns exec ${NETNS} ip link delete veth0.${VLAN}
			sudo ip netns exec ${NETNS} ip route delete default
			IP=$(random_ip)/24
			GW=${IP%.*}.254
		done
		echo "Name: $NAME, VLAN: $VLAN, IP: $IP, GW: $GW"
	done
}

# generate random ip addresses for namespaces
random_ip () {
	local MIN=1
	local MAX=254
	local RANGE=$((MAX - MIN))

	local OCTET1=$((MIN + RANDOM % RANGE))
	local OCTET2=$((MIN + RANDOM % RANGE))
	local OCTET3=$((MIN + RANDOM % RANGE))
	local OCTET4=$((MIN + RANDOM % RANGE))

	# random ipv4 address
	echo ${OCTET1}.${OCTET2}.${OCTET3}.${OCTET4}
}

new_mikrotik_config () {
	local FILE=mikrotik.rsc
	local IFACE=ether2

	[ -f "${FILE}" ] && rm ${FILE}
	touch ${FILE}

	for NETNS in $(sudo ip netns list | grep "ci690-" | awk '{print $1}'); do
		[ -n "${NETNS}" ] || continue
		local NAME=${NETNS#ci690-}

		local GW=$(sudo ip netns exec ${NETNS} ip -br route | grep "default" | awk '{print $3}')
		local VLAN=$(sudo ip netns exec ${NETNS} ip -d link show | grep vlan | awk '{print $5}')

		echo "/interface/vlan add name=vlan$VLAN vlan-id=$VLAN interface=$IFACE" >> $FILE
		echo "/ip/address add address=$GW/24 interface=vlan$VLAN" >> $FILE
	done

	# start server for router to download config
	python3 -m http.server
}

# simulate 'legitimate' web traffic to target server
traffic_gen () {
	local WEB=$1
	mapfile -t NETNS < <(ip netns list | awk '{print $1}')
	#local NETNS=(ci690-1 ci690-2 ci690-3 ci690-4 ci690-5)
	local PATHS=(
		"/" 
	  	"/index.php" 
	  	"/index.html" 
	  	"/login" 
	  	"/about" 
	  	"/favicon.ico" 
	  	"/api/status"
  	)
	local USER_AGENTS=(
		"Mozilla/5.0"
	  	"curl/8.5.0"
	  	"Wget/1.21.4"
	  	"Mozilla/5.0 (X11; Linux x86_64)"
	)

	while true; do
		# random sleep interval
		sleep_time=0.$(( RANDOM % 1000 ))
		sleep $sleep_time

		# Pick random namespace
		ns="${NETNS[$(( RANDOM % ${#NETNS[@]} ))]}"

		# Pick random path
		path="${PATHS[$(( RANDOM % ${#PATHS[@]} ))]}"

		# Pick random user agent
		ua="${USER_AGENTS[$(( RANDOM % ${#USER_AGENTS[@]} ))]}"

		echo "[*] $(date '+%F %T') namespace=$ns GET http://$WEB$path"

		sudo ip netns exec "$ns" \
			curl -A "$ua" \
			     --max-time 5 \
			     --silent \
			     --output /dev/null \
			     "http://$WEB$path"

	done
}
