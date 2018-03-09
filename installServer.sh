#!/bin/sh
#@Ubuntu 16.04

if [ "$UID" -ne "0" ]
then
   echo "start this script on root"
   exit 2
fi

echo "##################################"
echo "#                                #"
echo "#        Installation of         #"
echo "#                                #"
echo "#          Aker-Gateway          #"
echo "#                                #"
echo "##################################"


NEXT=0 #Pour boucler l'optention des paramètres si envie de boucle il y a
while [ $NEXT -eq 0 ]
do
        echo "**** get parameters ****"

        echo "Enter your public key."
        echo "This will allow you to log in to the aker account"
        read pubkey
        while [ -z $pubkey ]
        do
				echo 'You must enter a public SSH key: ' 
                read pubkey
        done

        echo "**** Parameter for redundancy ****"
		echo ""
		echo "++++ List of available network interfaces ++++"
		echo ""
        ifconfig -a | sed 's/[ \t].*//;/^\(lo\|\)$/d'
		echo "+++++++++++++++++++++++++++++++++++++++++++++++++"

        read -p "Which interface points outwards? " interface
        while [ -z $interface ]
        do
                read -p "Veuillez entrer un nom d'interface : " interface
        done
		
        read -p "What is the IP virtual address common to both machines (and mask) (example: 10.0.10.21/24) " virtualip
        while [ -z $virtualip ]
        do
                read -p "Please enter a virtual IP and its mask : " virtualip
        done

        read -p "What is the real IP address of this server?" realip
        while [ -z $realip ]
        do
                read -p "Please enter the IP of this server: " realip
        done
		
		read -p "What is the real IP address of the other server?" ipothersrv
        while [ -z $ipothersrv ]
        do
                read -p "Please enter the IP of the other server: " ipothersrv
        done
		
		read -p "What is the broadcast address of this server?" brdip
        while [ -z $brdip ]
        do
                read -p "Please enter the broadcast IP of this server: " brdip
        done


        read -p "Server must be \"slave\" or \"master\" ? [BACKUP / MASTER / help] " state
        if [[ $state == "help" ]]; then
                echo "The master is the server that will be reachable via the virtual IP address"
                echo "The slave server (BACKUP) will take over when the master server is unreachable."
                echo "However, in order to avoid interruptions when the master server is reachable again, the slave server keeps the hand until the master server is in turn unreachable."
        fi

        while [ -z $state ] || [[ $state != "BACKUP" ]] && [[ $state != "MASTER" ]]
        do
                read -p  "erver must be \"slave\" (BACKUP) or \"master\" (MASTER) ? : " state
        done

        echo "public key : " $pubkey
        echo "outward interface : " $interface
        echo "Virtual IP and its mask : " $virtualip
        echo "IP of this server : " $realip
        echo "IP of the other server : " $ipothersrv
        echo "Broadcast address : " $brdip
        echo "Type of redundancy server : " $state

		
        read -p "This parameters are correct ? [y/n] : " finalfield
        while [ -z $finalfield ] || [[ $finalfield == "y" ]] && [[ $finalfield == "n" ]]
        do		
				read -p "This parameters are correct ? [y/n] : " finalfield
        done
        if [[ $finalfield == "y" ]]; then
                NEXT=1
        fi

done

echo "**** Installing the necessary packages ****"

apt -y update
apt -y upgrade 
apt -y install python-paramiko python-configparser python-redis python-urwid python-wcwidth redis-server git iptables-persistent

echo "**** Redundancy installation and configuration ****"


# Ajout de deux lignes pour la configuration de glusterfs
echo "NEED_STATD=no" >> /etc/default/nfs-common
echo "NEED_IDMAPD=no" >> /etc/default/nfs-common

sed -i  -e 's|<REAL_IP>|'${realip}'|'  conf/automount-log.service
sed -i  -e 's|<REAL_IP>|'${realip}'|'  conf/automount-data.service
cp conf/automount-log.service /etc/systemd/system/
cp conf/automount-data.service /etc/systemd/system/

echo "**** Installation of aker ****"

mv scripts/* /usr/bin/
chmod +x /usr/bin/aker*

git clone https://github.com/aker-gateway/Aker.git /usr/bin/aker/


chmod 755 /usr/bin/aker/aker.py
chmod 755 /usr/bin/aker/akerctl.py

#Need this command to create glusterfs storage driver
#mkdir /var/log/aker
#touch /var/log/aker/aker.log
#chmod -R 777 /var/log/aker

mkdir -p /aker/{log,data}

echo "**** SSH configuration ****"

echo "Match Group *,!root,!bastion,!ubuntu,!bastionssh" >> /etc/ssh/sshd_config
echo "ForceCommand /usr/bin/aker/aker.py" >> /etc/ssh/sshd_config

systemctl restart ssh
systemctl restart redis

echo "**** Aker configuraton ****"

mkdir /etc/aker/
cp /usr/bin/aker/aker.ini /etc/aker/

sed -i 's/IPA/Json/' /etc/aker/aker.ini
sed -i 's/gateways/bastion/' /etc/aker/aker.ini
sed -i 's/ServerKeyBits 1024/ServerKeyBits 4096/' /etc/ssh/sshd_config
sed -i 's/PermitRootLogin without-password/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i 's/PasswordAuthentification yes/PasswordAuthentification no/' /etc/ssh/sshd_config
sed -i 's/#AuthorizedKeysFile/AuthorizedKeysFile/' /etc/ssh/sshd_config

echo "**** Add aker user ****"
adduser --disabled-password --gecos "" bastionssh
adduser --disabled-password --gecos "" bastion
echo bastion:Change-me-please | chpasswd
echo "##################################"
echo "#                                #"
echo "#    bastion account password    #"
echo "#                                #"
echo "#        Change-me-please        #"
echo "#                                #"
echo "##################################"

echo "bastion ALL=(root) /bin/cat, /usr/bin/vim, /usr/bin/vi, /bin/nano, /bin/echo, /bin/cd, /bin/ls, /usr/bin/aker/akerctl.py, /usr/bin/akerHost, /usr/bin/akerUser, /usr/bin/akerUsergroups" >> /etc/sudoers 
echo "bastionssh ALL=(root) NOPASSWD: /bin/bash, /bin/cat, /bin/mkdir, /bin/chown, /bin/cp, /usr/sbin/adduser, /bin/chown, /bin/mv, /usr/sbin/useradd" >> /etc/sudoers

mkdir /home/bastion/.ssh
touch /home/bastion/.ssh/authorized_keys
echo $pubkey > /home/bastion/.ssh/authorized_keys

mkdir -p /etc/aker/conf/users
mkdir -p /etc/aker/conf/hosts
touch /etc/aker/conf/usergroups
echo "\"default\"" > /etc/aker/conf/usergroups

echo "**** Configuring redundancy ****"

mkdir /etc/keepalived/
cp keepalivedConf/keepalived.service /lib/systemd/system/keepalived.service
cp keepalivedConf/keepalived.conf /etc/keepalived/
sed -i  -e 's|<STATE>|'${state}'|' \
                -e 's|<INTERFACE>|'${interface}'|' \
                -e 's|<VIRTUAL_IP>|'${virtualip}'|' \
                -e 's|<REAL_IP>|'${realip}'|' \
                -e 's|<hostname>|'${HOSTNAME}'|' /etc/keepalived/keepalived.conf

#enable keepalived
systemctl systemctl daemon-reload
systemctl enable keepalived.service
systemctl enable automount-log.service
systemctl enable automount-data.service
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
echo "net.ipv4.ip_nonlocal_bind=1" >> /etc/sysctl.conf
sysctl -p /etc/sysctl.conf

cp -R default /etc/aker
touch /etc/aker/hosts.json

echo "**** Creating the bastionssh usage ****"
adduser --disabled-password --gecos "" bastionssh
mkdir -p /home/bastionssh/.ssh/
ssh-keygen -b 4096 -t rsa -N '' -f /home/bastionssh/.ssh/id_rsa
cp -R /home/bastionssh/.ssh/ /root
chown -R bastionssh:bastionssh /home/bastionssh/.ssh/
chown bastionssh:bastionssh /home
echo "**** Configuring Access to Other Servers ****"

cat /home/bastionssh/.ssh/id_rsa.pub

read -p "Did you copy the SSH key? [y/n] : " copySSH
while [ -z $copySSH ] || [[ $finalfield == "y" ]] && [[ $finalfield == "n" ]]
do		
	read -p "Did you copy the SSH key? [y/n] : " copySSH
done


addgroup sshusers


echo $state > /etc/keepalived/state

apt purge -y build-essential libssl-dev

echo "**** iptables configuration ****"

# Interdire toute connexion entrante et sortante

# Autoriser RELATED et ESTABLISHED
# Tuer INVALID
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A INPUT -m state --state INVALID -j DROP
iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT -m state --state INVALID -j DROP

# Laisser certains types ICMP
iptables -A INPUT -p icmp --icmp-type destination-unreachable -j ACCEPT
iptables -A INPUT -p icmp --icmp-type source-quench -j ACCEPT
iptables -A INPUT -p icmp --icmp-type time-exceeded -j ACCEPT
iptables -A INPUT -p icmp --icmp-type parameter-problem -j ACCEPT
iptables -A INPUT -p icmp --icmp-type echo-request -j ACCEPT

# Configuration pare feu GlusterFS
iptables -I INPUT -m state --state NEW -m tcp -p tcp --dport 24007:24010 -j ACCEPT
iptables -I INPUT -m state --state NEW -m tcp -p tcp --dport 111 -j ACCEPT
iptables -I INPUT -m state --state NEW -m udp -p udp --dport 111 -j ACCEPT

iptables -I OUTPUT -m state --state NEW -m tcp -p tcp --dport 24007:24010 -j ACCEPT
iptables -I OUTPUT -m state --state NEW -m tcp -p tcp --dport 111 -j ACCEPT
iptables -I OUTPUT -m state --state NEW -m udp -p udp --dport 111 -j ACCEPT

iptables -A INPUT -m state --state NEW -m tcp -p tcp --dport 49152:49160 -j ACCEPT
iptables -A OUTPUT -m state --state NEW -m tcp -p tcp --dport 49152:49160 -j ACCEPT

# Redis
iptables -A INPUT -m state --state NEW -m tcp -p tcp --dport 6379 -j ACCEPT
iptables -A OUTPUT -m state --state NEW -m tcp -p tcp --dport 6379 -j ACCEPT

# SSH In
iptables -A INPUT -p tcp --dport 22 -j ACCEPT
iptables -A OUTPUT -p tcp --dport 22 -j ACCEPT

# DNS In/Out
iptables -A OUTPUT -p udp --dport 53 -j ACCEPT
iptables -A OUTPUT -p tcp --dport 53 -j ACCEPT

# Pour laisser l'accès aux mises à jour
iptables -A OUTPUT -p tcp --dport 80 -j ACCEPT
iptables -A OUTPUT -p tcp --dport 443 -j ACCEPT

iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT ACCEPT

iptables-save > /etc/iptables/rules.v4

ip6tables -P INPUT DROP
ip6tables -P FORWARD DROP
ip6tables -P OUTPUT DROP

ip6tables-save > /etc/iptables/rules.v6

echo "##################################"
echo "#                                #"
echo "#                                #"
echo "#                                #"
echo "#     Configuration finished     #"
echo "#                                #"
echo "#         Server restart         #"
echo "#                                #"
echo "#                                #"
echo "##################################"

sleep 30s

reboot