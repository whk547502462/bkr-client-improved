#!/bin/bash

export LANG=C
P=${0##*/}
#-------------------------------------------------------------------------------
Usage() {
	echo "Usage: $P [-b] [-d <distro>] [--kdc] [2012|2016]"
}
_at=`getopt -a -o hbd: \
	--long help \
	--long kdc \
	--long bridge \
	--long distro: \
    -n "$P" -- "$@"`
eval set -- "$_at"

while true; do
	case "$1" in
	-h|--help)    Usage; shift 1; exit 0;;
	-b|--bridge)  BRIDGE=-b; shift 1;;
	-d|--distro)  DISTRO=$2; shift 2;;
	--kdc)        KDC=--enable-kdc; shift 1;;
	--)           shift; break;;
	esac
done

winVer=${1:-2012}

echo -e "Info: checking dependence ..."
which nc &>/dev/null || dep=nmap-ncat
which vncviewer &>/dev/null || dep+=\ realvnc-vnc-viewer
[[ -n $dep ]] && {
	echo "Warn: you need install $dep first, try:" >&2
	echo "    sudo yum install -y $dep" >&2
	exit 1
}

echo -e "\nInfo: submit request to beaker ..."
baseUrl=http://pkgs.devel.redhat.com/cgit/tests/kernel/plain
submitlog=$(runtest ${DISTRO:-RHEL-7.5} "--cmd=wget $baseUrl/Library/base/tools/build_win_vm.sh -O /win.sh; bash /win.sh --winver=$winVer -- $BRIDGE $KDC --vm-name win-$winVer --disk-size 60 answerfiles-cifs-nfs/*;" --hr-alias=vmhost)
echo "$submitlog"
job=$(egrep -o J:[0-9]+ <<<"$submitlog")
[[ -z $job ]] && {
	echo "Error: didn't get beaker job ID" >&2
	exit 1
}

echo -e "\nInfo: waiting beaker job getting machine ..."
while ! [[ "$jobstatus" = Install* ]]; do
	jobstatus=$(bkr job-results $job --prettyxml | sed -r -n '/<job .* status="([^"]*)".*/{s//\1/;p}')
	echo "Job status: $jobstatus"
	[[ "$jobstatus" = Aborted || "$jobstatus" = Can* ]] && {
		echo "Error: beaker job Aborted or Cancelled, please check distro and try again" >&2
		exit 1
	}
	sleep 10
done
host=$(bkr job-results $job --prettyxml | sed -r -n '/.*system="([^"]*)".*/{s//\1/;p}')
[[ -z $host ]] && {
	echo "Error: didn't get beaker job host info" >&2
	exit 1
}

echo -e "\nInfo: waiting windows vm start install ..."
#while ! nc -z $host 7788; do sleep 10; echo -n .; done
while ! nc $host 7788 </dev/null &>/dev/null; do sleep 10; echo -n .; done


echo -e "\nvncviewer $host:7788 ..."
vncviewer $host:7788 -Encryption=PreferOff
