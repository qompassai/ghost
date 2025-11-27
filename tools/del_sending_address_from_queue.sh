#!/bin/sh
#/qompassai/ghost/tools/del_sending_address_from_queue.sh
# --------------------------------------
# Copyright (C) 2025 Qompass AI, All rights reserved
(test "$1" != "") || (echo "Need email address to delete from queue" && exit 1)
for i in `mailq | grep "$1" | awk '{print $1;}' | sed -e 's/\*//'`; do postsuper -d $i; done
