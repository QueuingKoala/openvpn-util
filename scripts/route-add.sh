#!/bin/sh

# Copyright 2018 Josh Cepek <josh.cepek AT usa.net>
#
# This code is available under the 3-Clause BSD License.
#
# For full licensing text, see the project LICENSE file, or visit:
#
# https://opensource.org/licenses/BSD-3-Clause

# PURPOSE:
#
# OpenVPN route addition backend.
#
# Designed to be invoked from --route-up and used with --route-noexec

# ARGS:
#
# none required: see option processing section for possibilities.

# TODO: some program help output should be added at some point.

IP=/sbin/ip
DEBUG=0

debug() { [ "$DEBUG" -ge 1 ] && warn "ip-r-DBG: $*"; }
warn() { printf "%s\n" "$@" >&2; }
die() { warn "$1"; exit "${2:-1}"; }

# Options processing section.
# All params default to NULL except metric, which will come from openvpn if available.
tos= table= proto= scope= metric= weight=
while [ $# -ge 1 ]; do
	case "$1" in
		-tos)
			tos="$2"
			shift ;;
		-table)
			table="$2"
			shift ;;
		-proto)
			proto="$2"
			shift ;;
		-scope)
			scope="$2"
			shift ;;
		-metric)
			metric="$2"
			shift ;;
		-weight)
			weight="$2"
			shift ;;
		-debug)
			DEBUG=$((DEBUG+1)) ;;
		*)
			die "invalid option: $1"
	esac
	shift
done

# OpenVPN supplies IPv4 nets as a doted-quad mask; this prints the CIDR value.

mask_to_cidr_v4() {
	local quad cidr x IFS
	IFS=.
	cidr=0
	for quad in $*
	do
		x=0
		case "$quad" in
			0)	break ;;
			128)	x=1 ;;
			192)	x=2 ;;
			224)	x=3 ;;
			240)	x=4 ;;
			248)	x=5 ;;
			252)	x=6 ;;
			254)	x=7 ;;
			255)	x=8 ;;
			*)
				debug "bad-quad: $quad"
				return 1
		esac
		cidr=$((cidr+x))
	done
	echo $cidr
}

rc=0
for af in route route_ipv6; do
	i=1
	while { net=$(eval echo \$${af}_network_$i); [ -n "$net" ]; }
	do
		# v4 dotted-quad mask to CIDR, and append to network:
		if [ "$af" = "route" ]; then
			mask=$(eval echo \$route_netmask_$i)
			cidr=$(mask_to_cidr_v4 "$mask") || {
				warn "Ignoring bogus mask from: $net $mask"
				rc=$((rc+1)) i=$((i+1))
				continue
			}
			net="$net/$cidr"
		fi

		# gateway
		gw=$(eval echo \$${af}_gateway_$i)

		# Prefer CLI metric, but use env-var if no CLI option.
		[ -z "$metric" ] && metric=$(eval echo \$${af}_metric_$i)

		for cmd in debug "$IP"; do
			"$cmd" route add "$net" \
				${tos:+tos "$tos"} \
				${table:+table "$table"} \
				${proto:+proto "$proto"} \
				${scope:+scope "$scope"} \
				${metric:+metric "$metric"} \
				${gw:+via "$gw"} \
				dev "$dev" \
				${weight:+weight "$weight"}
		done
		
		if [ $? -ne 0 ]; then
			warn "Failed ip command for: $net"
			rc=$((rc+1))
		fi
		i=$((i+1))
	done
done

exit "$rc"

