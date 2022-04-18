#!/bin/sh
USERS="$(cut -d: -f 1 /etc/passwd)"

for u in $USERS
do
	passwd -S $u | grep -Ew "NP" >/dev/null
	if [ $? -eq 0 ]; then
		passwd -l $u
	fi
done

