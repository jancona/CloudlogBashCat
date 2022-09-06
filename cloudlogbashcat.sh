#! /bin/bash

# cloudlogbashcat.sh 
# A simple script to keep Cloudlog in synch with rigctld or flrig.
# Copyright (C) 2018  Tony Corbett, G0WFV
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301  USA

DEBUG=0

rigFreq=0
rigOldFreq=1

rigMode="MATCH"
rigOldMode="NO MATCH"

delay=1

# load in config ...
source cloudlogbashcat.conf

simpleArg() {
    local arg="$1"
    local type=${arg%%:*} val=${arg#*:}
        echo -e "${indent}<param><value><$type>$val</$type></value></param>"
}

structArg() {
    local arg="$1"
        : parse wait complete ...
}

generateRequestXml() {
    method=$1; shift
    echo '<?xml version="1.0"?>'
    echo "<methodCall>"
    echo "    <methodName>$method</methodName>"
    echo "    <params>"

    indent="    "
    for arg; do
        indent="${indent}    "
        case $arg in
        struct:*) structArg "$arg";;
        *) simpleArg "$arg";;
        esac
    done

    echo "    </params>"
    echo "</methodCall>"
}

while true; do
	case $rigControlSoftware in
		rigctld)
			# Get rigctld frequency, mode and bandwidth - accepts multiple commands
			# rigctl returns the results on separate lines
			# https://stackoverflow.com/a/32931403 describes how we read that
			IFS=$'\n' read -r -d '' -a out < <( rigctl -r $host:$port -m 2 f m && printf '\0' )
			rigFreq=${out[0]}
			rigMode=${out[1]}
			rigWidth=${out[2]}
			;;

		flrig)
			# Get flrig frequency ...
			rpcxml=$(generateRequestXml "rig.get_vfo")
			rigFreq=$(curl -k $verbose --data "$rpcxml" "$host:$port" 2>/dev/null | xmllint --format --xpath '//value/text()' - 2>&1)

			if [[ $? -ne 0 ]]; then
				echo "Unable to contact server" >&2
				exit 1
			fi

			# Get flrig mode ...
			rpcxml=$(generateRequestXml "rig.get_mode")
			rigMode=$(curl -k $verbose --data "$rpcxml" "$host:$port" 2>/dev/null | xmllint --format --xpath '//value/text()' -)
			;;

		*)
			echo "Unknown rig control server type" >&2
			exit 1
			;;
	esac
		
  if [ $rigFreq -ne $rigOldFreq  ] || [ "$rigMode" != "$rigOldMode"  ]; then
    # rig freq or mode changed, update Cloudlog
    [[ $DEBUG -eq 1 ]] && printf  "%-10d   %-6s\n" $rigFreq $rigMode
    rigOldFreq=$rigFreq
    rigOldMode=$rigMode

    curl --silent --insecure \
         --header "Content-Type: application/json" \
         ${cloudlogHttpAuth:+"--header"} \
         ${cloudlogHttpAuth:+"Authorization: $cloudlogHttpAuth"} \
         --request POST \
         --data "{ 
           \"key\":\"$cloudlogApiKey\",
           \"radio\":\"$cloudlogRadioId\",
           \"frequency\":\"$rigFreq\",
           \"mode\":\"$rigMode\",
           \"timestamp\":\"$(date +"%Y/%m/%d %H:%M")\"
         }" $cloudlogApiUrl >/dev/null 2>&1
  fi

	sleep $delay
done

