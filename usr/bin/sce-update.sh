#!/bin/busybox ash
# (c) Jason Williams 2014
# Tool to update SCE extensions in bulk.

. /etc/init.d/tc-functions
checknotroot
TCEDIR=/etc/sysconfig/tcedir
SCEDIR="/etc/sysconfig/tcedir/sce"
DEBINXDIR="/etc/sysconfig/tcedir/import/debinx"
BUILD=`getBuild`
unset DEPLIST

if [ "$1" == "-h" ] || [ "$1" == "--help" ]; then
        echo " "
	echo "${YELLOW}sce-update - Check and update all or individual SCE(s) including any dependency"
	echo "             SCE(s), view DEBINX (Debian index) diff and available updates if"
	echo "             desired, may use some option combinations.${NORMAL}"
	echo " "
	echo "Usage:"
	echo " "
	echo "${YELLOW}"sce-update"${NORMAL}         Menu prompt, choose SCE(s) to check, update if required."
       	echo "${YELLOW}"sce-update SCE"${NORMAL}     Check a specific SCE for update, update if required."
	echo "${YELLOW}"sce-update -a"${NORMAL}      Check all system SCEs for updates, view old/new DEBINX diff"
	echo "                   and available updates if desired, update SCEs if required."
	echo "${YELLOW}"sce-update -n SCE"${NORMAL}  Non-interactive mode, check a specific SCE for updates,"
	echo "                   update if required."
	echo "${YELLOW}"sce-update -na"${NORMAL}     Non-interactive mode, check all SCEs for updates,"
	echo "                   update if required."
	echo "${YELLOW}"sce-update -c"${NORMAL}      Menu prompt, check selected SCE(s) for updates only,"
        echo "                   no actual updates performed."
	echo "${YELLOW}"sce-update -r"${NORMAL}      Unpack files in RAM during an SCE update re-import."
	echo "${YELLOW}"sce-update -s"${NORMAL}      Estimate package, HD and RAM space during an SCE update"
	echo "                   re-import, warn as needed."
	echo "${YELLOW}"sce-update -z"${NORMAL}      Ignore /etc/sysconfig/sceconfig preferences, use only"
        echo "                   current command line options."
	echo "${YELLOW}"sce-update -b"${NORMAL}      Check SCE entries in your sceboot.lst and any"
	echo "                   applicable SCE dependencies."
	echo "${YELLOW}"sce-update -f"${NORMAL}      This flags an SCE for update on the first found package"
	echo "                   or startup script needing and update and moves to the next SCE"
	echo "                   for quicker performance"
	echo " "
	exit 0
fi


if [ -f /tmp/.scelock ]; then
	LOCK=`cat /tmp/.scelock`
	if /bb/ps | /bb/grep "$LOCK " | /bb/grep -v grep > /dev/null 2>&1; then
		echo "Another SCE utility is presently in use, exiting.."
		exit 1
	fi
fi

echo "$$" > /tmp/.scelock

while getopts canrszbf OPTION
do
	case ${OPTION} in
		r) RAM=TRUE ;;
		n) NONINTERACTIVE=TRUE ;;
		c) CHECKONLY=TRUE ;;
		a) UPDATEALL=TRUE ;;
		s) SIZE=TRUE ;;
		z) NOCONFIG=TRUE ;;
		b) SCEBOOTLIST=TRUE ;;
		f) FASTCHECK=TRUE ;;
                *) echo "Run  sce-update --help  for usage information."
                   exit 1 ;;
	esac
done

# Determine if non-interactive mode is being used.
if grep -i "^NONINTERACTIVE=TRUE" /etc/sysconfig/sceconfig > /dev/null 2>&1 && [ "$NOCONFIG" != "TRUE" ]; then
	NONINTERACTIVE=TRUE
fi

shift `expr $OPTIND - 1`
UPDATETARGET=`basename "$1" .sce`
OPTIONS=""
if [ "$RAM" == "TRUE" ]; then
	OPTIONS=""$OPTIONS"r"
fi

if [ "$SIZE" == "TRUE" ]; then
	OPTIONS=""$OPTIONS"s"
fi

if [ -z "$1" ] && [ "$SCEBOOTLIST" != "TRUE" ]; then
	SELECT=TRUE
fi

[ -f /tmp/.updatefastcheck ] && sudo rm /tmp/.updatefastcheck
if [ "$FASTCHECK" == "TRUE" ]; then
	touch /tmp/.updatefastcheck
fi

if [ "$SCEBOOTLIST" == "TRUE" ]; then
	if [ -n "$1" ]; then
		echo "The -b option is not to be used with a specified SCE, exiting.."
		exit 1
	fi
fi

if [ "$SCEBOOTLIST" == "TRUE" ] && [ "$UPDATEALL" == "TRUE" ]; then
	echo "The -a and -b options cannot be used together, exiting.."
	exit 1
fi

if [ -n "$2" ]; then
     echo "Only one SCE per sce-update session can be entered in command line."
     echo "Run 'sce-update' to check more than one SCE per session, exiting.."
     exit 1
fi

[ -d /tmp/work ] && sudo rm -r /tmp/work
[ -f /tmp/.sceupdatechoose ] && sudo rm /tmp/.sceupdatechoose
[ -f /tmp/.scelistchoose ] && sudo rm /tmp/.scelistchoose
[ -f /tmp/.sceupdateall ] && sudo rm /tmp/.sceupdateall
[ -f /tmp/.sceupdatelist ] && sudo rm /tmp/.sceupdatelist
[ -f /tmp/select.ans ] && sudo rm /tmp/select.ans
[ -f /tmp/.importupdates ] && sudo rm /tmp/.importupdates
[ -f /tmp/updateavailable ] && sudo rm /tmp/updateavailable
[ -f /tmp/importupdated ] && sudo rm /tmp/importupdated
[ -f /tmp/.importpkgtype ] && sudo rm /tmp/.importpkgtype
[ -f /tmp/.updatechecked ] && sudo rm /tmp/.updatechecked

cleanup() {
	sudo chown -R "$TCUSER":staff "$SCEDIR" 
	[ -f /tmp/.updatefastcheck ] && sudo rm /tmp/.updatefastcheck
	[ -f /tmp/.sceupdatechoose ] && sudo rm /tmp/.sceupdatechoose
	[ -f /tmp/.scelistchoose ] && sudo rm /tmp/.scelistchoose
	[ -f /tmp/.sceupdateall ] && sudo rm /tmp/.sceupdateall
	[ -f /tmp/.sceupdatelist ] && sudo rm /tmp/.sceupdatelist
	[ -f /tmp/select.ans ] && sudo rm /tmp/select.ans
	[ -f /tmp/.importupdates ] && sudo rm /tmp/.importupdates
	[ -f /tmp/importupdates ] && sudo rm /tmp/importupdates
	[ -f /tmp/ssupdates ] && sudo rm /tmp/ssupdates
	ls /tmp/*.md5sum > /dev/null 2>&1 && sudo rm /tmp/*.md5sum
	[ -f /tmp/.importpkgtype ] && sudo rm /tmp/.importpkgtype
	[ -f /tmp/.prebuiltmd5sumlist ] && sudo rm /tmp/.prebuiltmd5sumlist
	[ -f /tmp/.pkgextrafilemd5sumlist ] && sudo rm /tmp/.pkgextrafilemd5sumlist
	[ -f /tmp/.pkgprebuilt ] && sudo rm /tmp/.pkgprebuilt
	[ -f /tmp/.updatechecked ] && sudo rm /tmp/.updatechecked
	[ -d /tmp/work ] && sudo rm -r /tmp/work
	sudo rm /tmp/*suggested > /dev/null 2>&1
	sudo rm /tmp*recommended > /dev/null 2>&1
}

cd /etc/sysconfig/tcedir/sce

exit_tcnet() {
	echo " "
	echo "There is an issue connecting to `cat /opt/tcemirror`, exiting.."
	exit 1
}


read IMPORTMIRROR < /opt/tcemirror
PREBUILTMIRROR="${IMPORTMIRROR%/}/dCore/"$BUILD"/import"
IMPORTMIRROR="${IMPORTMIRROR%/}/dCore/import"

sudo debGetEnv "$2"
if [ "$?" != "0" ]; then
	echo " "
	echo "Error updating DEBINX files, exiting.."
	exit 1
fi
read DEBINX < /etc/sysconfig/tcedir/import/debinx/debinx

cd "$SCEDIR"

## Get recursive list of dependency SCEs.
getDeps() {
DEPLIST=" $1 $DEPLIST "

if [ -f "$SCEDIR"/"$1".sce.dep ]; then
	for E in `cat "$SCEDIR"/"$1".sce.dep`; do
		H=" $E "
		if echo "$DEPLIST" | grep "$H" > /dev/null 2>&1; then
			continue
		else
			getDeps "$E"
		fi
	done
fi
}
##

if [ "$UPDATEALL" == "TRUE" ]; then
	
##### OLDDEBINX, NEWDEBINX
#####
	cd /etc/sysconfig/tcedir/import/debinx
	if [ -f OLDDEBINX ]; then
		MDOLD=`md5sum OLDDEBINX | cut -f1 -d" "`
	else
		MDOLD="0"
	fi
	MDNEW=`md5sum NEWDEBINX | cut -f1 -d" "`
	if [ "$MDOLD" == "$MDNEW" ]; then
		echo " "
		echo "The entire SCE directory is up to date."
		sudo rm NEWDEBINX
		exit 0
	elif [ ! "$NONINTERACTIVE" == "TRUE" ]; then
		echo " "
		if [ ! -f "$DEBINXDIR"/OLDDEBINX ]; then
			echo "No "$DEBINXDIR"/OLDDEBINX available for comparison,"
			echo -n "recommend press Enter to proceed with update check, Ctrl-C aborts: "
			read ans
			echo " "
			:
		else
			echo "Press Enter to proceed with update check, (v)iew DEBINX diff, Ctrl-C aborts"
			echo -n "(to view DEBINX diff use spacebar and (q)uit): "
			read ans
			echo " "
			if [ "$ans" == "v" ] || [ "$ans" == "V" ]; then
				echo "Obtaining diff of new and old package data..."
				echo " "
				diff "$DEBINXDIR"/OLDDEBINX "$DEBINXDIR"/NEWDEBINX > /dev/null 2>&1 > /tmp/debinx.diff & /usr/bin/rotdash $!
				more -s /tmp/debinx.diff
				rm /tmp/debinx.diff
				echo " "
				echo -n "Press Enter to proceed with update check, Ctrl-C aborts: "
				read ans
				echo " "
			fi
		fi
	fi

	

##### /OLDDEBINX, NEWDEBINX
#####	

	cd "$SCEDIR"
	echo "Checking all system SCEs for updates:"
	echo " "
	## Get list of SCEs to be updated, should be all.
	for I in `ls *.sce | sed 's:.sce$::' | sort`; do
		if [ -f update/"$I".sce.debinx ] && [ -f update/"$I".sce.md5.txt ]; then
			MDNEW=`md5sum /etc/sysconfig/tcedir/import/debinx/NEWDEBINX | cut -f1 -d" "`
			MDOLD=`cat update/"$I".sce.debinx`
			if [ "$MDOLD" == "$MDNEW" ]; then
				echo "         ${YELLOW}"$I".sce${NORMAL} is up to date."
				continue
			fi
		elif [ -f "$I".sce.debinx ] && [ -f "$I".sce.md5.txt ]; then
			MDNEW=`md5sum /etc/sysconfig/tcedir/import/debinx/NEWDEBINX | cut -f1 -d" "`
			MDOLD=`cat "$I".sce.debinx`
			if [ "$MDOLD" == "$MDNEW" ]; then
				echo "         ${YELLOW}"$I".sce${NORMAL} is up to date."
				continue
			fi
		fi
		echo "         ${YELLOW}"$I".sce${NORMAL} update check..."
		importupdatecheck "$I" > /dev/null 2>&1 & /usr/bin/rotdash $!
	done
	if [ -s /tmp/.sceupdatelist ]; then
		if [ "$CHECKONLY" != "TRUE" ]; then
			if [ "$NONINTERACTIVE" == "TRUE" ]; then
				for I in `cat /tmp/.sceupdatelist`; do
					if [ -f /tmp/"$I".recommended ]; then
						OPTIONS="$OPTIONS"R
					fi
					if [ -f /tmp/"$I".suggested ]; then
						OPTIONS="$OPTIONS"S
					fi
					if ! grep "^$I$" /tmp/importupdated > /dev/null 2>&1; then
						sce-import -"$OPTIONS"Nnp "$I"
						#if [ "$?" != "0" ]; then
						#	echo "Error in updating "$I", exiting.."
						#	exit 1
						#fi
					fi
					echo "$I" >> /tmp/importupdated
				done
			else
				echo " "
				echo "Update check completed."
				echo " "
				cat  /tmp/.sceupdatelist | sort | uniq
				echo " "
                                echo -n "Press Enter to update above SCE(s), (v)iew package updates, Ctrl-C aborts: "
				read ans
				echo " "
				if [ "$ans" == "v" ] || [ "$ans" == "V" ]; then
					more -s /tmp/updateavailable
					echo " "
					echo -n "Press Enter to proceed with updates, Ctrl-C aborts: "
					read ans
					echo " "
				fi
				for I in `cat /tmp/.sceupdatelist`; do
					if [ -f /tmp/"$I".recommended ]; then
						OPTIONS="$OPTIONS"R
					fi
					if [ -f /tmp/"$I".suggested ]; then
						OPTIONS="$OPTIONS"S
					fi
					if ! grep "^$I$" /tmp/importupdated > /dev/null 2>&1; then
						sce-import -"$OPTIONS"Nnp "$I"
						#if [ "$?" != "0" ]; then
						#	echo "Error in updating "$I", exiting.."
						#	exit 1
						#fi
					fi
					echo "$I" >> /tmp/importupdated
				done
			fi
		else
			echo " "
			echo "Update check completed."
			echo " "
			cat  /tmp/.sceupdatelist | sort | uniq
			echo " "
			echo -n "Press Enter to view package updates, Ctrl-C aborts: "
			read ans
			if [ "$ans" == "" ]; then
				more -s /tmp/updateavailable
			fi
			exit 0
		fi
	else
		echo " "
		echo "No updates available for main or any dependency SCEs."
	fi
	cd /etc/sysconfig/tcedir/import/debinx
	sudo mv NEWDEBINX OLDDEBINX > /dev/null 2>&1
	##
elif [ "$SCEBOOTLIST" == "TRUE" ]; then
	echo " "
	if [ -n "$1" ]; then
		echo "The -b option is not to be used with a specified SCE, exiting.."
		exit 1
	fi	
	for i in `cat /proc/cmdline`; do
		case $i in
			lst=*) TARGETLIST=${i#*=} ;;
		esac
	done
	[ -n "$TARGETLIST" ] || TARGETLIST="sceboot.lst"
	for I in `cat "$TCEDIR"/"$TARGETLIST"`; do
		getDeps "$I"
	done
	for I in `echo "$DEPLIST"`; do
		if [ -f update/"$I".sce.debinx ] && [ -f update/"$I".sce.md5.txt ]; then
			MDNEW=`md5sum /etc/sysconfig/tcedir/import/debinx/NEWDEBINX | cut -f1 -d" "`
			MDOLD=`cat update/"$I".sce.debinx`
			if [ "$MDOLD" == "$MDNEW" ]; then
				echo "         ${YELLOW}"$I".sce${NORMAL} is up to date."
				continue
			fi
		elif [ -f "$I".sce.debinx ] && [ -f "$I".sce.md5.txt ]; then
			MDNEW=`md5sum /etc/sysconfig/tcedir/import/debinx/NEWDEBINX | cut -f1 -d" "`
			MDOLD=`cat "$I".sce.debinx`
			if [ "$MDOLD" == "$MDNEW" ]; then
				echo "         ${YELLOW}"$I".sce${NORMAL} is up to date."
				continue
			fi
		fi
		echo "         ${YELLOW}"$I".sce${NORMAL} update check..."
		importupdatecheck "$I" > /dev/null 2>&1 & /usr/bin/rotdash $!
	done
	if [ -s /tmp/.sceupdatelist ]; then
		if [ "$CHECKONLY" != "TRUE" ]; then
			if [ "$NONINTERACTIVE" == "TRUE" ]; then
				for I in `cat /tmp/.sceupdatelist`; do
					if [ -f /tmp/"$I".recommended ]; then
						OPTIONS="$OPTIONS"R
					fi
					if [ -f /tmp/"$I".suggested ]; then
						OPTIONS="$OPTIONS"S
					fi
					if ! grep "^$I$" /tmp/importupdated > /dev/null 2>&1; then
						sce-import -"$OPTIONS"Nnp "$I"
						#if [ "$?" != "0" ]; then
						#	echo "Error in updating "$I", exiting.."
						#	exit 1
						#fi
					fi
					echo "$I" >> /tmp/importupdated
				done
			else
				echo " "
				echo "Update check completed."
				echo " "
				cat  /tmp/.sceupdatelist | sort | uniq
				echo " "
                                echo -n "Press Enter to update above SCE(s), (v)iew package updates, Ctrl-C aborts: "
				read ans
				echo " "
				if [ "$ans" == "v" ] || [ "$ans" == "V" ]; then
					more -s /tmp/updateavailable
					echo " "
					echo -n "Press Enter to proceed with updates, Ctrl-C aborts: "
					read ans
					echo " "
				fi
				for I in `cat /tmp/.sceupdatelist`; do
					if [ -f /tmp/"$I".recommended ]; then
						OPTIONS="$OPTIONS"R
					fi
					if [ -f /tmp/"$I".suggested ]; then
						OPTIONS="$OPTIONS"S
					fi
					if ! grep "^$I$" /tmp/importupdated > /dev/null 2>&1; then
						sce-import -"$OPTIONS"Nnp "$I"
						#if [ "$?" != "0" ]; then
						#	echo "Error in updating "$I", exiting.."
						#	exit 1
						#fi
					fi
					echo "$I" >> /tmp/importupdated
				done
			fi
		else
			echo " "
			echo "Update check completed."
			echo " "
			cat  /tmp/.sceupdatelist | sort | uniq
			echo " "
			echo -n "Press Enter to view package updates, Ctrl-C aborts: "
			read ans
			if [ "$ans" == "" ]; then
				more -s /tmp/updateavailable
			fi
			exit 0
		fi
	else
		echo " "
		echo "No updates available for main or any dependency SCEs."
	fi
elif [ -f update/"$UPDATETARGET".sce ]; then
	#if [ -f update/"$UPDATETARGET".sce.debinx ] && [ -f update/"$UPDATETARGET".sce.md5.txt ]; then
	#	MDNEW=`md5sum /etc/sysconfig/tcedir/import/debinx/NEWDEBINX | cut -f1 -d" "`
	#	MDOLD=`cat update/"$UPDATETARGET".sce.debinx`
	#	if [ "$MDOLD" == "$MDNEW" ]; then
	#		echo "         ${YELLOW}"$UPDATETARGET".sce${NORMAL} is up to date."
	#		exit 0
	#	fi
	#fi
	cd update/
	echo "Searching for available updates for "$UPDATETARGET".sce."
	unset DEPLIST
	getDeps "$UPDATETARGET"
	for I in `echo "$DEPLIST"`; do
		if [ -f update/"$I".sce.debinx ] && [ -f update/"$I".sce.md5.txt ]; then
			MDNEW=`md5sum /etc/sysconfig/tcedir/import/debinx/NEWDEBINX | cut -f1 -d" "`
			MDOLD=`cat update/"$I".sce.debinx`
			if [ "$MDOLD" == "$MDNEW" ]; then
				echo "         ${YELLOW}"$I".sce${NORMAL} is up to date."
				continue
			fi
		elif [ -f "$I".sce.debinx ] && [ -f "$I".sce.md5.txt ]; then
			MDNEW=`md5sum /etc/sysconfig/tcedir/import/debinx/NEWDEBINX | cut -f1 -d" "`
			MDOLD=`cat "$I".sce.debinx`
			if [ "$MDOLD" == "$MDNEW" ]; then
				echo "         ${YELLOW}"$I".sce${NORMAL} is up to date."
				continue
			fi
		fi
		echo "         ${YELLOW}"$I".sce${NORMAL} update check..."
		importupdatecheck "$I" > /dev/null 2>&1 & /usr/bin/rotdash $!
	done
	if [ -s /tmp/.sceupdatelist ]; then
		if [ "$CHECKONLY" != "TRUE" ]; then
			if [ "$NONINTERACTIVE" == "TRUE" ]; then
				for I in `cat /tmp/.sceupdatelist`; do
					if [ -f /tmp/"$I".recommended ]; then
						OPTIONS="$OPTIONS"R
					fi
					if [ -f /tmp/"$I".suggested ]; then
						OPTIONS="$OPTIONS"S
					fi
					if ! grep "^$I$" /tmp/importupdated > /dev/null 2>&1; then
						sce-import -"$OPTIONS"Nnp "$I"
						#if [ "$?" != "0" ]; then
						#	echo "Error in updating "$I", exiting.."
						#	exit 1
						#fi
					fi
					echo "$I" >> /tmp/importupdated
				done
			else
				echo " "
				echo "Update check completed."
				echo " "
				cat  /tmp/.sceupdatelist | sort | uniq
				echo " "
                                echo -n "Press Enter to update above SCE(s), (v)iew package updates, Ctrl-C aborts: "
				read ans
				echo " "
				if [ "$ans" == "v" ] || [ "$ans" == "V" ]; then
					more -s /tmp/updateavailable
					echo " "
					echo -n "Press Enter to proceed with updates, Ctrl-C aborts: "
					read ans
					echo " "
				fi
				for I in `cat /tmp/.sceupdatelist`; do
					if [ -f /tmp/"$I".recommended ]; then
						OPTIONS="$OPTIONS"R
					fi
					if [ -f /tmp/"$I".suggested ]; then
						OPTIONS="$OPTIONS"S
					fi
					if ! grep "^$I$" /tmp/importupdated > /dev/null 2>&1; then
						sce-import -"$OPTIONS"Nnp "$I"
						#if [ "$?" != "0" ]; then
						#	echo "Error in updating "$I", exiting.."
						#	exit 1
						#fi
					fi
					echo "$I" >> /tmp/importupdated
				done
			fi
		else
			echo " "
			echo "Update check completed."
			echo " "
			cat  /tmp/.sceupdatelist | sort | uniq
			echo " "
			echo -n "Press Enter to view package updates, Ctrl-C aborts: "
			read ans
			if [ "$ans" == "" ]; then
				more -s /tmp/updateavailable
			fi
			exit 0
		fi
	else
		echo " "
		echo "No updates available for "$UPDATETARGET".sce or any dependency SCE(s)."
	fi
	cd ..
elif [ -f "$UPDATETARGET".sce ]; then
	#if [ -f "$UPDATETARGET".sce.debinx ] && [ -f "$UPDATETARGET".sce.md5.txt ]; then
	#	MDNEW=`md5sum /etc/sysconfig/tcedir/import/debinx/NEWDEBINX | cut -f1 -d" "`
	#	MDOLD=`cat "$UPDATETARGET".sce.debinx`
	#	if [ "$MDOLD" == "$MDNEW" ]; then
	#		echo " "
	#		echo "${YELLOW}"$UPDATETARGET".sce${NORMAL} is up to date."
	#		exit 0
	#	fi
	#fi
	echo " "
	echo "Searching for available updates for ${YELLOW}"$UPDATETARGET".sce${NORMAL}."
	unset DEPLIST
	getDeps "$UPDATETARGET"
	for I in `echo "$DEPLIST"`; do
		if [ -f update/"$I".sce.debinx ] && [ -f update/"$I".sce.md5.txt ]; then
			MDNEW=`md5sum /etc/sysconfig/tcedir/import/debinx/NEWDEBINX | cut -f1 -d" "`
			MDOLD=`cat update/"$I".sce.debinx`
			if [ "$MDOLD" == "$MDNEW" ]; then
				echo "         ${YELLOW}"$I".sce${NORMAL} is up to date."
				continue
			fi
		elif [ -f "$I".sce.debinx ] && [ -f "$I".sce.md5.txt ]; then
			MDNEW=`md5sum /etc/sysconfig/tcedir/import/debinx/NEWDEBINX | cut -f1 -d" "`
			MDOLD=`cat "$I".sce.debinx`
			if [ "$MDOLD" == "$MDNEW" ]; then
				echo "         ${YELLOW}"$I".sce${NORMAL} is up to date."
				continue
			fi
		fi
		echo "         ${YELLOW}"$I".sce${NORMAL} update check..."
		importupdatecheck "$I" > /dev/null 2>&1 & /usr/bin/rotdash $!
	done
	if [ -s /tmp/.sceupdatelist ]; then
		if [ "$CHECKONLY" != "TRUE" ]; then
			if [ "$NONINTERACTIVE" == "TRUE" ]; then
				for I in `cat /tmp/.sceupdatelist`; do
					if [ -f /tmp/"$I".recommended ]; then
						OPTIONS="$OPTIONS"R
					fi
					if [ -f /tmp/"$I".suggested ]; then
						OPTIONS="$OPTIONS"S
					fi
					if ! grep "^$I$" /tmp/importupdated > /dev/null 2>&1; then
						sce-import -"$OPTIONS"Nnp "$I"
						#if [ "$?" != "0" ]; then
						#	echo "Error in updating "$I", exiting.."
						#	exit 1
						#fi
					fi
					echo "$I" >> /tmp/importupdated
				done
			else
				echo " "
				echo "Update check completed."
				echo " "
				cat  /tmp/.sceupdatelist | sort | uniq
				echo " "
				echo -n "Press Enter to update above SCE(s), (v)iew package updates, Ctrl-C aborts: "
				read ans
				echo " "
				if [ "$ans" == "v" ] || [ "$ans" == "V" ]; then
					more -s /tmp/updateavailable
					echo " "
					echo -n "Press Enter to proceed with updates, Ctrl-C aborts: "
					read ans
					echo " "
				fi
				for I in `cat /tmp/.sceupdatelist`; do
					if [ -f /tmp/"$I".recommended ]; then
						OPTIONS="$OPTIONS"R
					fi
					if [ -f /tmp/"$I".suggested ]; then
						OPTIONS="$OPTIONS"S
					fi
					if ! grep "^$I$" /tmp/importupdated > /dev/null 2>&1; then
						sce-import -"$OPTIONS"Nnp "$I"
						#if [ "$?" != "0" ]; then
						#	echo "Error in updating "$I", exiting.."
						#	exit 1
						#fi
					fi
					echo "$I" >> /tmp/importupdated
				done
			fi
		else
			echo " "
			echo "Update check completed."
			echo " "
			cat  /tmp/.sceupdatelist | sort | uniq
			echo " "
			echo -n "Press Enter to view package updates, Ctrl-C aborts: "
			read ans
			if [ "$ans" == "" ]; then
				more -s /tmp/updateavailable
			fi
			exit 0
		fi
	else
		echo " "
		echo "No updates available for "$UPDATETARGET".sce or any dependency SCE(s)."
	fi
	
	
elif [ "$SELECT" == "TRUE" ]; then
	ls *.sce | sed 's:.sce$::' | sort > /tmp/.scelistchoose
	while true; do
		[ ! -s /tmp/.scelistchoose ] && break
		cat /tmp/.scelistchoose | select2 "Choose SCE(s) to update check, press Enter with no selection to proceed." "-"
		read ANS < /tmp/select.ans
		if [ "$ANS" == "" ]; then
			break
		fi
		grep "^$ANS$" /tmp/.sceupdatechoose > /dev/null 2>&1 || echo "$ANS" >> /tmp/.sceupdatechoose
		sed -i "/^$ANS$/d" /tmp/.scelistchoose
	done
	##
	echo " "
	if [ ! -s /tmp/.sceupdatechoose ]; then
		echo " "
		echo "No SCEs chosen for update check, exiting.."
		exit 0
	fi
	cat /tmp/.sceupdatechoose | tr -d :
	echo " "
	echo -n "Press Enter to update check above SCE(s), (q)uit to exit: "
	read ANS
	echo " "
	if [ "$ANS" == "q" ] || [ "$ANS" == "Q" ]; then
		cleanup
		exit 0
	else
		## Update selected SCEs
		for D in `cat /tmp/.sceupdatechoose | tr -d :`; do
			echo "Checking ${YELLOW}"$D".sce${NORMAL}..."
			unset DEPLIST
			getDeps "$D"
			for I in `echo "$DEPLIST"`; do
				UPDATETARGET="$I"
				if [ -f update/"$I".sce.debinx ] && [ -f update/"$I".sce.md5.txt ]; then
					MDNEW=`md5sum /etc/sysconfig/tcedir/import/debinx/NEWDEBINX | cut -f1 -d" "`
					MDOLD=`cat update/"$I".sce.debinx`
					if [ "$MDOLD" == "$MDNEW" ]; then
						echo "         ${YELLOW}"$I".sce${NORMAL} is up to date."
							continue
					fi
				elif [ -f "$I".sce.debinx ] && [ -f "$I".sce.md5.txt ]; then
					MDNEW=`md5sum /etc/sysconfig/tcedir/import/debinx/NEWDEBINX | cut -f1 -d" "`
					MDOLD=`cat "$I".sce.debinx`
					if [ "$MDOLD" == "$MDNEW" ]; then
						echo "         ${YELLOW}"$I".sce${NORMAL} is up to date."
						continue
					fi
				fi
				echo "         ${YELLOW}"$I".sce${NORMAL} update check..."
				importupdatecheck "$I" > /dev/null 2>&1 & /usr/bin/rotdash $!
			done
		done
		if [ -s /tmp/.sceupdatelist ]; then
			if [ "$CHECKONLY" != "TRUE" ]; then
				if [ "$NONINTERACTIVE" == "TRUE" ]; then
					for I in `cat /tmp/.sceupdatelist`; do
						if [ -f /tmp/"$I".recommended ]; then
							OPTIONS="$OPTIONS"R
						fi
						if [ -f /tmp/"$I".suggested ]; then
							OPTIONS="$OPTIONS"S
						fi
						if ! grep "^$I$" /tmp/importupdated > /dev/null 2>&1; then
							sce-import -"$OPTIONS"Nnp "$I"
							#if [ "$?" != "0" ]; then
							#	echo "Error in updating "$I", exiting.."
							#	exit 1
							#fi
						fi
						echo "$I" >> /tmp/importupdated
					done
				else
					echo " "
					echo "Update check completed."
					echo " "
					cat  /tmp/.sceupdatelist | sort | uniq
					echo " "
					echo -n "Press Enter to update above SCE(s), (v)iew package updates, Ctrl-C aborts: "
					read ans
					echo " "
					if [ "$ans" == "v" ] || [ "$ans" == "V" ]; then
						more -s /tmp/updateavailable
						echo " "
						echo -n "Press Enter to proceed with updates, Ctrl-C aborts: "
						read ans
						echo " "
					fi
					for I in `cat /tmp/.sceupdatelist`; do
						if [ -f /tmp/"$I".recommended ]; then
							OPTIONS="$OPTIONS"R
						fi
						if [ -f /tmp/"$I".suggested ]; then
							OPTIONS="$OPTIONS"S
						fi
						if ! grep "^$I$" /tmp/importupdated > /dev/null 2>&1; then
							sce-import -"$OPTIONS"Nnp "$I"
							#if [ "$?" != "0" ]; then
							#	echo "Error in updating "$I", exiting.."
							#	exit 1
							#fi
						fi
						echo "$I" >> /tmp/importupdated
					done
				fi
			else
				echo " "
				echo "Update check completed."
				echo " "
				cat  /tmp/.sceupdatelist | sort | uniq
				echo " "
				#echo -n "Press Enter to view package updates, Ctrl-C aborts: "
				#read ans
				#if [ "$ans" == "" ]; then
					more -s /tmp/updateavailable
				#fi
				exit 0
			fi
		else
			:
		fi
			unset DEPLIST
		if [ ! -s /tmp/.sceupdatelist ]; then
			echo " "
			echo "No updates available for chosen SCE(s) at this time."
			exit 0
		else
			echo " "
			echo -n "Press Enter to review packages that had updates available, (n)o to exit: "
			read ans
			if [ "$ans" == "" ]; then
				more -s /tmp/updateavailable
			fi			
			exit 0
		fi
	fi
else
	echo " "
	echo ""$UPDATETARGET" is not an existing SCE file, exiting.."
fi

cleanup

if ls /tmp/*.pkglist > /dev/null 2>&1; then
	sudo rm /tmp/*.pkglist
fi

if ls /tmp/*.md5new > /dev/null 2>&1; then
	sudo rm /tmp/*.md5new
fi

if ls /tmp/*.deb2sce > /dev/null 2>&1; then
	sudo rm /tmp/*.deb2sce
fi

