#!/bin/bash -ex

# Please run that script as root !

# Passwords and variables, please edit them if needed!
nova_password="stack0n"
ip_controller=""

if [ -z "$ip_controller" ]; then echo "Please set an IP for the controller node! Thanks!" && exit 1; fi

if [[ $EUID -ne 0 ]]; then
    echo "This script is design to be run as the root user!"
    echo "Log in as the root user!"
    exit 1
fi

# You can choose between different virtualisation engines, like:
# kvm, qemu, lxc, uml and xen
virt="qemu"

# Environment variables
ip=`ifconfig eth0 |grep "inet addr" |awk '{print $2}' |awk -F: '{print $2}'`

echo "Let's install an OpenStack Havana compute node! ########"
apt-get update && apt-get -y install ntp python-mysqldb ubuntu-cloud-keyring
echo "ntpdate $ip_controller
hwclock -w" > /etc/cron.daily/ntpdate
echo "deb http://ubuntu-cloud.archive.canonical.com/ubuntu precise-updates/havana main" > /etc/apt/sources.list.d/cloud-archive.list
apt-get update && apt-get -y dist-upgrade

echo "NOVA INSTALL ########"
sleep 2
export DEBIAN_FRONTEND=noninteractive
apt-get -q -y install nova-compute-$virt python-novaclient python-guestfs
chmod 0644 /boot/vmlinuz*
rm /var/lib/nova/nova.sqlite
echo "my_ip=$ip
#VNC
novnc_enabled=true
novncproxy_base_url=http://127.0.0.1:6080/vnc_auto.html
novncproxy_port=6080
vncserver_proxyclient_address=127.0.0.1
vncserver_listen=0.0.0.0
# GLANCE
image_service=nova.image.glance.GlanceImageService
glance_api_servers=$ip:9292
glance_host=$ip_controller
rabbit_host = $ip_controller
rabbit_port = 5672" >> /etc/nova/nova.conf
sed -i s,'auth_host = 127.0.0.1',"auth_host = $ip_controller",g /etc/nova/api-paste.ini
sed -i s,%SERVICE_TENANT_NAME%,service,g /etc/nova/api-paste.ini
sed -i s,%SERVICE_USER%,nova,g /etc/nova/api-paste.ini
sed -i s,%SERVICE_PASSWORD%,$nova_password,g /etc/nova/api-paste.ini

echo "RESTART NOVA-COMPUTE SERVICE... ########"
service nova-compute restart

echo "NOVA CONFIGURATION DONE! ########"

echo ""
echo "This script took $SECONDS seconds to finish!"
