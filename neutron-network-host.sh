#!/bin/bash -ex

# Please run that script as root !

# Passwords and variables, please edit them if needed!
ip_controller=""
mysql_password="stack0m"
neutron_password="stack0n"
token='stack0t'

if [[ $EUID -ne 0 ]]; then
    echo "This script is design to be run as the root user!"
    echo "Log in as the root user!"
    exit 1
fi

if [ -z "$ip_controller" ]; then echo "Please set an IP for the controller node! Thanks!" && exit 1; fi

# Environment variables
ip=`ifconfig eth0 |grep "inet addr" |awk '{print $2}' |awk -F: '{print $2}'`
keystone_creds="--os-token=$token --os-endpoint=http://$ip:35357/v2.0"

echo "Let's install an OpenStack Havana network node! ########"
apt-get update && apt-get -y install ntp python-mysqldb ubuntu-cloud-keyring
echo "ntpdate $ip_controller
hwclock -w" > /etc/cron.daily/ntpdate
echo "deb http://ubuntu-cloud.archive.canonical.com/ubuntu precise-updates/havana main" > /etc/apt/sources.list.d/cloud-archive.list
apt-get update && apt-get -y dist-upgrade

echo "NEUTRON INSTALL ########"
sleep 2
apt-get -y install neutron-server neutron-dhcp-agent neutron-plugin-openvswitch neutron-l3-agent
sed -i s,#net.ipv4.ip_forward=1,net.ipv4.ip_forward=1,g /etc/sysctl.conf
sed -i s,#net.ipv4.conf.default.rp_filter=1,net.ipv4.conf.default.rp_filter=0,g /etc/sysctl.conf
sed -i s,#net.ipv4.conf.all.rp_filter=1,net.ipv4.conf.all.rp_filter=0,g /etc/sysctl.conf
service networking restart

echo "CREATE NEUTRON DATABASE ########"
mysql -uroot -p$mysql_password -e "CREATE DATABASE neutron"
mysql -uroot -p$mysql_password -e "GRANT ALL PRIVILEGES ON neutron.* TO 'neutron'@'localhost' IDENTIFIED BY '$neutron_password';"
##NEED IF
mysql -uroot -p$mysql_password -e "GRANT ALL PRIVILEGES ON neutron.* TO 'neutron'@'chef-client.tld.invalid' IDENTIFIED BY '$neutron_password';"
mysql -uroot -p$mysql_password -e "GRANT ALL PRIVILEGES ON neutron.* TO 'neutron'@'%' IDENTIFIED BY '$neutron_password';"
echo "FLUSH MYSQL PRIVILEGES ########"
mysql -uroot -p$mysql_password -e "flush privileges"

echo "CREATE NEUTRON USER IN KEYSTONE ########"
keystone $keystone_creds user-create --name=neutron --pass=$neutron_password --email=neutron@example.com
echo "ADD ROLE ADMIN TO NEUTRON USER ########"
keystone $keystone_creds user-role-add --user=neutron --tenant=service --role=admin

echo "SETUP NEUTRON SERVICE FOR KEYSTONE ########"
neutron_id=`keystone $keystone_creds service-create --name=neutron --type=network --description="OpenStack Networking Service" |grep -w id |awk '{print $4}'`
echo "SETUP NEUTRON ENDPOINT ########"
keystone $keystone_creds endpoint-create --service-id=$neutron_id --publicurl=http://$ip:9696 --internalurl=http://$ip:9696 --adminurl=http://$ip:9696

echo "UPDATE CONFIGURATIONS FILES ########"
sed -i s,'auth_host = 127.0.0.1',"auth_host = $ip_controller",g /etc/neutron/neutron.conf
sed -i s,%SERVICE_TENANT_NAME%,service,g /etc/neutron/neutron.conf
sed -i s,%SERVICE_USER%,neutron,g /etc/neutron/neutron.conf
sed -i s,%SERVICE_PASSWORD%,$neutron_password,g /etc/neutron/neutron.conf
sed -i s,'connection = sqlite:////var/lib/neutron/neutron.sqlite',"connection = mysql://neutron:$neutron_password@$ip/neutron",g /etc/neutron/neutron.conf
echo "[filter:authtoken]
paste.filter_factory=keystoneclient.middleware.auth_token:filter_factory
auth_host=$ip_controller
admin_user=neutron
admin_tenant_name=service
admin_password=$neutron_password" >> /etc/neutron/api-paste.ini
echo "[database]
connection = mysql://neutron:$neutron_password@$ip/neutron" >> /etc/neutron/plugins/openvswitch/ovs_neutron_plugin.ini
sed -i s,'# Example: firewall_driver = neutron.agent.linux.iptables_firewall.OVSHybridIptablesFirewallDriver','firewall_driver = neutron.agent.linux.iptables_firewall.OVSHybridIptablesFirewallDriver',g /etc/neutron/plugins/openvswitch/ovs_neutron_plugin.ini

echo "INSTALL OPEN VSWITCH ########"
apt-get -y install openvswitch-switch neutron-plugin-openvswitch-agent chkconfig
service openvswitch-switch start
chkconfig openvswitch-switch on
ovs-vsctl add-br br-int

echo "NEUTRON CONFIGURATION DONE! ########"

echo ""
echo "This script took $SECONDS seconds to finish!"
