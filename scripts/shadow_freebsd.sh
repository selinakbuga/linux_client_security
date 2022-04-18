#!/bin/bash
USERS="$(awk -F: 'NF > 1 && $1 !~ /^[#+-]/ && $2=="" {print $0}' /etc/master.passwd | cut -d: -f1)"
for u in $USERS
do
	pw lock $u
done
