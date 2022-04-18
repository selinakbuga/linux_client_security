#!/bin/bash

cat /etc/passwd | awk -F: '($3 == 0) { print $1 }' 
