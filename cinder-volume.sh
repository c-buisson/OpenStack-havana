#!/bin/bash -ex

# Please run that script as root !

#This script assume that Cinder-api and Cinder-scheduler are running on the controller node.
#It also assumes that this server has 2 disks: /dev/sda and /dev/sdb.

# Passwords and variables, please edit them if needed!
cinder_password="stack0c"
ip_controller=""

if [[ $EUID -ne 0 ]]; then
    echo "This script is design to be run as the root user!"
    echo "Log in as the root user!"
    exit 1
fi

if [ -z "$ip_controller" ]; then echo "Please set an IP for the controller node! Thanks!" && exit 1; fi

# Environment variables
ip=`ifconfig eth0 |grep "inet addr" |awk '{print $2}' |awk -F: '{print $2}'`

echo "Let's install an OpenStack Havana cinder-volume node! ########"
apt-get update && apt-get -y install ntp python-mysqldb ubuntu-cloud-keyring
echo "ntpdate $ip_controller
hwclock -w" > /etc/cron.daily/ntpdate
echo "deb http://ubuntu-cloud.archive.canonical.com/ubuntu precise-updates/havana main" > /etc/apt/sources.list.d/cloud-archive.list
apt-get update && apt-get -y dist-upgrade

echo "CINDER INSTALL ########"
sleep 2
apt-get -y install cinder-volume lvm2
sed -i s,'auth_host = 127.0.0.1',"auth_host = $ip_controller",g /etc/cinder/api-paste.ini
sed -i s,%SERVICE_TENANT_NAME%,service,g /etc/cinder/api-paste.ini
sed -i s,%SERVICE_USER%,cinder,g /etc/cinder/api-paste.ini
sed -i s,%SERVICE_PASSWORD%,$cinder_password,g /etc/cinder/api-paste.ini
echo "rpc_backend = cinder.openstack.common.rpc.impl_kombu
rabbit_host = $ip_controller
rabbit_port = 5672" >> /etc/cinder/cinder.conf

echo "CREATING LVM PHYSICAL VOLUME ########"
pvcreate /dev/sdb
vgcreate cinder-volumes /dev/sdb

echo "EDIT LVM.CONF FILE ########"
sed -i 's/filter = \[ "a\/.*\/" \]/filter = \[ "a\/sda1\/", "a\/sdb1\/", "r\/.*\/"\]/g' /etc/lvm/lvm.conf

echo "RESTART CINDER-VOLUME AND TGT SERVICES... ########"
service cinder-volume restart
service tgt restart

echo "CINDER CONFIGURATION DONE! ########"

echo ""
echo "This script took $SECONDS seconds to finish!"
