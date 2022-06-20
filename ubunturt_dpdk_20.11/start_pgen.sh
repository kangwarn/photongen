#!/bin/bash
# Script start container with DPDK pktgen in interactive mode.
#
#   First check Docker file and make sure container in 
#   local image registry.
#  
#   DPKD kernel module: Scripts requires uio_pci_generic, 
#   The test-pmd will use a device node that will be added by uio_pci_generic interface 
#   and therefore it must be bounded by DPKD.
#   
#   Hugepages: test-pmd and DPKD requires hugepages, make sure you do it 
#   either manually or use init.sh script.
#
# - Script will gets list of all cores and construct a range from low to hi
# - by default it will use all cores.
#
# - Script checks if interface already bounded by kernel driver and shutdown
#   will shutdown kernel interface and re-bind dpdk. 
#
# - Script will a pass pci device to container.
#
# - It wil also check hugepages and passed dev to container.
#
# - Normally you want start two VM, each VM will need run test-pmd
#   default mode set to txonly, in case of two VM's and two seperate container
#   one container generate traffic and another container reciever.
#
# Author Mustafa Bayramov 

default_device0="/dev/uio0"
default_peer_mac="00:50:56:b6:0d:dc"
default_forward_mode="txonly"
default_img_name="photon_dpdk20.11:v1"
default_dev_hugepage="/dev/hugepages"
default_dpkd_bind="/usr/local/bin"
default_rxq="4"
default_txq="4"
#--stats-period PERIOD

command -v numactl >/dev/null 2>&1 || \
	{ echo >&2 "Require numactl but it's not installed.  Aborting."; exit 1; }
command -v ifconfig >/dev/null 2>&1 || \
	{ echo >&2 "Require ifconfig but it's not installed.  Aborting."; exit 1; }
command -v lspci >/dev/null 2>&1 || \
	{ echo >&2 "Require lspci but it's not installed.  Aborting."; exit 1; }
command -v lshw >/dev/null 2>&1 || \
	{ echo >&2 "Require lshs but it's not installed.  Aborting."; exit 1; }
command -v dpdk-devbind.py >/dev/null 2>&1 || \
	{ echo >&2 "Require foo but it's not installed.  Aborting."; exit 1; }

# get list of all cores and numa node
# pass entire range of lcores to DPKD
nodes=$(numactl --hardware | grep cpus | tr -cd "[:digit:] \n")
[[ -z "$nodes" ]] && { echo "Error: numa nodes string empty"; exit 1; }

IFS=', ' read -r -a nodelist <<< "$nodes"
numa_node="${nodelist[0]}"
numa_lcores="${nodelist[@]:1}"
numa_low_lcore="${nodelist[0]}"
numa_hi_lcore="${nodelist[-1]}"

echo "Using numa node" "$numa_node"
echo "List of cores in system" "$numa_lcores" "lcore range $numa_low_lcore - $numa_hi_lcore"

[[ -z "$numa_node" ]] && { echo "Error: numa node value empty"; exit 1; }
[[ -z "$numa_low_lcore" ]] && { echo "Error: numa lower bound for num lcore is empty"; exit 1; }
[[ -z "$numa_hi_lcore" ]] && { echo "Error: numa upper bound for num lcore is empty"; exit 1; }

# Prompt for peer mac address.
echo -n "Do wish to use default peer mac address program (y/n)? "
read -r default_mac

if [ "$default_mac" != "${default_mac#[Yy]}" ] ;then
    echo "Using default peer mac" $default_peer_mac
else
	echo -n "Peer mac address (format 00:50:56:b6:0d:dc): "
    read -r client_mac
	[[ -z "$client_mac" ]] && { echo "Error: mac address is empty string"; exit 1; }
	default_peer_mac=$client_mac
fi

echo -n "Using peer mac address: " "$default_peer_mac"

# Take first VF and use it as target device.
#  - if device already bounded by kernel unload and bind DPKD.
pci_dev=$(lspci -v | grep "Virtual Function" | awk '{print $1}')
[[ -z "$pci_dev" ]] && { echo "Error: pci device not found. Check lspci -v"; exit 1; }

eth_dev=$(lshw -class network -businfo | grep "$pci_dev" | awk '{print $2}')

if [ "$eth_dev" == "network" ]; then
	echo " A pci device $pci_dev already unbounded from kernel."
	eth_up="DOWN"
else
	eth_up=$(ifconfig eth1 | grep BROADCAST | awk '{print $1}')
fi

if [ "$eth_up" == "UP" ]; then
	echo "A pci device $pci_dev $eth_dev is bounded by kernel as $eth_up"
	ifconfig "$eth_dev" down
	$default_dpkd_bind/dpdk-devbind.py -b uio_pci_generic "$pci_dev"
else
	#is_loadded=$(/usr/local/bin/dpdk-devbind.py -s | grep $pci_dev | grep drv=uio_pci_generic)
	$default_dpkd_bind/dpdk-devbind.py -b uio_pci_generic "$pci_dev"
fi

if [ -c "$default_device0" ]; then
	echo "Attaching $default_device0."
fi

if [ -d "$default_dev_hugepage" ]; then
	docker run --privileged --name photon_testpmd --device=/sys/bus/pci/devices/* \
		-v "$default_dev_hugepage":/dev/hugepages  \
		--cap-add=SYS_RAWIO --cap-add IPC_LOCK \
		--cap-add NET_ADMIN --cap-add SYS_ADMIN \
		--cap-add SYS_NICE \
		--rm \
		-i -t $default_img_name pktgen \
		-l "$numa_low_lcore-$numa_hi_lcore" --proc-type auto --log-level 7 \
		--file-prefix pg -- -T --crc-strip
else
	"Warrning. Create hugepages in respected numa node."
fi