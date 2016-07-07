#!/bin/sh

# udhcpc script edited by Tim Riker <Tim@Rikers.org>

[ -z "$1" ] && echo "Error: should be called from udhcpc" && exit 1

RESOLV_CONF="/etc/resolv.conf"
[ -n "$broadcast" ] && BROADCAST="broadcast $broadcast"
[ -n "$subnet" ] && NETMASK="netmask $subnet"

case "$1" in
	deconfig)
		ip addr flush dev $interface
		ip link set dev $interface up
		;;
	renew|bound)
		ip addr add dev $interface local $ip/$mask $BROADCAST

		if [ -n "$router" ] ; then
			while ip route del default 2>/dev/null ; do
			    :
			done

			metric=0
			for i in $router ; do
				ip route add default via $i metric $((metric++))
			done
		fi

		echo -n > $RESOLV_CONF
		[ -n "$domain" ] && echo search $domain >> $RESOLV_CONF
		for i in $dns ; do
			echo adding dns $i
			echo nameserver $i >> $RESOLV_CONF
		done
		;;
esac

exit 0
