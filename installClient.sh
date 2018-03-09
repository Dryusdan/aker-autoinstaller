#!/bin/sh
if [ "$UID" -ne "0" ]
then
   echo "Il faut executer ce script en root"
   exit 1
fi
echo "Quel est l'ip du bastion ?"
read ipBastion
iptables -A INPUT -p tcp -s $ipBastion --dport 22 -j ACCEPT
iptables -A INPUT -p tcp -s 0.0.0.0/0 --dport 22 -j DROP