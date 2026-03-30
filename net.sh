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
	new_bridge

	for i in {1..5}; do
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

touch_server () {
	local NAME=$1
	local SERV_IP=$2
	local NETNS=ci690-${NAME}
	sudo ip netns exec ${NETNS} bash -c "for i in {1..5}; do curl ${SERV_IP} > /dev/null 2>&1; sleep 2; done"
}

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
	local IFACE_RIP=ether1
	local IFACE_LAN=ether2

	[ -f "${FILE}" ] && rm ${FILE}
	touch ${FILE}

	echo "/routing/rip/instance add name=black redistribute=connected,rip" >> $FILE
	echo "/routing/rip/interface-template add interface=$IFACE_RIP instance=black" >> $FILE

	for NETNS in $(sudo ip netns list | grep "ci690-" | awk '{print $1}'); do
		[ -n "${NETNS}" ] || continue
		local NAME=${NETNS#ci690-}

		local GW=$(sudo ip netns exec ${NETNS} ip -br route | grep "default" | awk '{print $3}')
		local VLAN=$(sudo ip netns exec ${NETNS} ip -d link show | grep vlan | awk '{print $5}')

		echo "/interface/vlan add name=vlan$VLAN vlan-id=$VLAN interface=$IFACE_LAN" >> $FILE
		echo "/ip/address add address=$GW/24 interface=vlan$VLAN" >> $FILE
	done

	# start server for router to download config
	python3 -m http.server
}
