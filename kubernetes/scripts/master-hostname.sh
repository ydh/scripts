#!/bin/bash

HOST_NAME=$(echo $(ifconfig ens3 |awk 'NR==2{print $2 }'|cut -d ":" -f2) | sed 's/\./\-/g')

hostnamectl set-hostname master-${HOST_NAME}