#!/bin/sh
#@Ubuntu 16.04

if [ "$UID" -ne "0" ]
then
   echo "You must run this script in root"
   exit 2
fi

read -p "What is the IP of the other server? " ip


read -p "What is the public key of the other server? " sshpubkey


echo $sshpubkey > /home/bastionssh/.ssh/authorized_keys
chown bastionssh:bastionssh /home/bastionssh/.ssh/authorized_keys

mkdir /var/log/aker
touch /var/log/aker/aker.log
chmod -R 777 /var/log/aker


if [ "`cat /etc/keepalived/state`" == "MASTER" ]; then
	echo "##################################"
	echo "#                                #"
	echo "#                                #"
	echo "#       Aker configuration       #"
	echo "#                                #"
	echo "#                                #"
	echo "##################################"

	cp -f data/usergroups /etc/aker/conf/usergroups

	bash data/users.sh
	
	while read line
	do
			NOM=`echo $line | awk -F";" '{ print $1 }'`
			GROUP=`echo $line | awk -F";" '{ print $2 }'`
			HOSTGROUP=`echo $line | awk -F";" '{ print $3 }'`
			akerHost add "$NOM" "$GROUP" "$HOSTGROUP"
	done < data/hosts.csv

	akerReload

	echo "##################################"
	echo "#                                #"
	echo "#                                #"
	echo "#     Configuration finished     #"
	echo "#                                #"
	echo "#                                #"
	echo "##################################"
fi