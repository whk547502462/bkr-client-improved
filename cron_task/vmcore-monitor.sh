#!/bin/bash
# Author: Jianhong Yin

expdir=$1
urlroot=$2
mailCc=${3:-jiyin@redhat.com}
mailFrom=jiyin@redhat.com

cd $expdir || exit 1
ls >/dev/null  # make sure autofs mount
expdir=$PWD

fstype=$(df -P -T $expdir | tail -n +2 | awk '{print $2}')
if [ "${fstype:0:3}" = nfs ]; then
	nfspath=$(df -P -T $expdir | tail -n +2 | awk '{print $1}')
else
	read nfsserv ignore <<<$(hostname -A)
	nfspath=$nfsserv:$expdir
fi

#list_today=$(find . -name vmcore -type f -mtime -1 |
#	awk -F/ '/(.*\.com)-([a-z-]+)-([0-9]+)/ {
#		match($2,/(.*\.com)-([a-z-]+)-([0-9]+)$/, a);
#		user=a[2];
#		jobhost=a[3]"-"a[1];
#		_[user][jobhost]++;
#	}
#	END {
#		for (i in _) {
#			printf(i);
#			for(j in _[i]) printf(" %s", j); printf("\n")
#		}
#	}'
#)
list_today_new=$(find . -name vmcore -type f -mtime -1 |
	awk -F/ '{
		user=$2;
		jobhost=$3"-"$4;
		_[user][jobhost]++;
	}
	END {
		for (i in _) {
			printf(i);
			for(j in _[i]) printf(" %s", j); printf("\n")
		}
	}'
)

while read owner jobid_host; do
	[ -z "$owner" -o -z "$jobid_host" ] && continue
	echo -e "$owner:"
	mailTo=$owner@redhat.com
	(
	echo -e "Hi $owner\n\nAs subject, there are some vmcores generated by your job\n- in $nfspath"
	for corepath in $jobid_host; do
		read jobid host <<< ${corepath/-/ }
		d=$host-$owner-$jobid
		dn=$owner/$jobid/$host
		test -d $d || d=$dn
		test -d $dn || continue

		echo -e "\n================"
		echo -e "Host -> https://beaker.engineering.redhat.com/view/$host"
		echo -e "Job  -> https://beaker.engineering.redhat.com/jobs/$jobid"
		bkr job-results --prettyxml J:$jobid >res$$.xml

		# output whiteboard info
		WB=$(grep '<whiteboard>' res$$.xml | sed -e 's/^[ \t]*//' -e 's/<.\?whiteboard>//g')
		ignorePanic=
		[[ "$WB" = *-ignore-panic* ]] && ignorePanic="(ignore panic)"
		echo -n "Whiteboard$ignorePanic ->"
		echo "$WB"

		# output recipe info
		echo -n "Recipe ->"
		grep system=.$host. res$$.xml |
			egrep -o '(arch|distro|status|whiteboard)="[^"]+"'| awk '{printf(" %s", $0)}'

		rm res$$.xml

		# vmcore files info
		echo -e "\n\n:  vmcore files:"
		for coref in $(find $d -name vmcore -type f); do
			access=$(stat -c  %A  $coref)
			[[ ${access:7:1} != r ]] && chmod a+r $coref

			echo -e ":      $urlroot/$coref"
			[[ -f $coref-dmesg.txt ]] && echo -e ":      $urlroot/$coref-dmesg.txt"
			echo
		done
	done
	echo -e "\nThis reminder is generated by vmcore-monitor, any suggestions/questions, please contant to jiyin@redhat.com\nThanks!"
	) | sendmail.sh -p '[vmcore remind] ' -f "$mailFrom" -t "${mailTo}" -c "$mailCc" - ": your($owner) beaker job generated new vmcore file[s] in past 24h"  &>/dev/null
done <<<"$list_today_new"
