#!/bin/bash
cat error_log | grep script | grep -oE "\b([0-9]{1,3}\.){3}[0-9]{1,3}\b" |
uniq > blockips.txt
sed 's/^/block drop from any to '/ blockips.txt > blockiplist.txt
cat blockiplist.txt >> /etc/pf.conf
date +"date--%d/%m/%Y" >> blockedips.txt
cat blockiplist.txt >> blockedips.txt
rm blockips.txt
rm blockiplist.txt
echo -n "" > error_log
pfctl -e -f /etc/pf.conf
