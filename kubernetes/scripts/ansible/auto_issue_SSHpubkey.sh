#!/usr/bin/env bash
set -e

user="root"
passwd="rootpasswd"

for i in `cat /scripts/serverip.txt`;do
    ./auto_ssh.sh $user $passwd $i
done