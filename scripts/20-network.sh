#!/bin/sh
# Bring up the internal bridge for jails. Does not touch the uplink NIC.
set -eu

sysrc gateway_enable=YES
sysrc cloned_interfaces="bridge0"
sysrc ifconfig_bridge="inet 10.0.0.1/24 up"

service netif cloneup
ifconfig bridge0 | grep -q 'inet 10.0.0.1' || ifconfig bridge0 inet 10.0.0.1/24 up
