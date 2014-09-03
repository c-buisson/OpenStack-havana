#!/bin/bash -ex

# Please run that script as root!
# This script will setup: Keystone, Glance, Nova-api/scheduler/cert/conductor/consoleauth/doc/ajax-console-proxy/novncproxy (with basic settings), Cinder, Horizon and Euca2ools.

# Passwords, please edit them if needed!
admin_pass="mypass"
mysql_password="stack0m"
keystone_password="stack0k"
glance_password="stack0g"
nova_password="stack0n"
cinder_password="stack0c"
token='stack0t'

# Environment variables
ip=`ifconfig eth0 |grep "inet addr" |awk '{print $2}' |awk -F: '{print $2}'`
keystone_creds="--os-token=$token --os-endpoint=http://$ip:35357/v2.0"

if [[ $EUID -ne 0 ]]; then
    echo "This script has been designed to be run as the root user!"
    echo "Log in as the root user!"
    exit 1
fi

echo "Let's install an OpenStack Havana controller node! ########"
apt-get update
export DEBIAN_FRONTEND=noninteractive
apt-get -q -y install ntp python-mysqldb mysql-server htop git iotop rabbitmq-server ubuntu-cloud-keyring euca2ools curl
echo "CHANGE PASSWORD MYSQL ########"
mysqladmin -u root password $mysql_password
sed -i s,127.0.0.1,$ip,g /etc/mysql/my.cnf
service mysql restart
echo "deb http://ubuntu-cloud.archive.canonical.com/ubuntu precise-updates/havana main" > /etc/apt/sources.list.d/cloud-archive.list
apt-get update && apt-get -y dist-upgrade

echo "STARTING ADD DBs and USERS ########"
sleep 2
echo "CREATE KEYSTONE DATABASE ########"
mysql -uroot -p$mysql_password -e "CREATE DATABASE keystone"
mysql -uroot -p$mysql_password -e "GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'localhost' IDENTIFIED BY '$keystone_password';"
mysql -uroot -p$mysql_password -e "GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'%' IDENTIFIED BY '$keystone_password';"
echo "CREATE GLANCE DATABASE ########"
mysql -uroot -p$mysql_password -e "CREATE DATABASE glance"
mysql -uroot -p$mysql_password -e "GRANT ALL PRIVILEGES ON glance.* TO 'glance'@'localhost' IDENTIFIED BY '$glance_password';"
mysql -uroot -p$mysql_password -e "GRANT ALL PRIVILEGES ON glance.* TO 'glance'@'%' IDENTIFIED BY '$glance_password';"
echo "CREATE NOVA DATABASE ########"
mysql -uroot -p$mysql_password -e "CREATE DATABASE nova"
mysql -uroot -p$mysql_password -e "GRANT ALL PRIVILEGES ON nova.* TO 'nova'@'localhost' IDENTIFIED BY '$nova_password';"
mysql -uroot -p$mysql_password -e "GRANT ALL PRIVILEGES ON nova.* TO 'nova'@'%' IDENTIFIED BY '$nova_password';"
echo "CREATE CINDER DATABASE ########"
mysql -uroot -p$mysql_password -e "CREATE DATABASE cinder"
mysql -uroot -p$mysql_password -e "GRANT ALL PRIVILEGES ON cinder.* TO 'cinder'@'localhost' IDENTIFIED BY '$cinder_password';"
mysql -uroot -p$mysql_password -e "GRANT ALL PRIVILEGES ON cinder.* TO 'cinder'@'%' IDENTIFIED BY '$cinder_password';"
echo "REMOVE ANONYMOUS USERS ########"
mysql -uroot -p$mysql_password -e "delete from user where user='';" mysql
echo "FLUSH MYSQL PRIVILEGES ########"
mysql -uroot -p$mysql_password -e "flush privileges"

echo "KEYSTONE INSTALL ########"
sleep 2
apt-get -y install keystone python-keystone python-keystoneclient
sed -i s,'# admin_token = ADMIN',"admin_token = $token",g /etc/keystone/keystone.conf
sed -i s,'connection = sqlite:////var/lib/keystone/keystone.db',"connection = mysql://keystone:$keystone_password@$ip/keystone",g /etc/keystone/keystone.conf
echo "KEYSTONE DB_SYNC ########"
keystone-manage db_sync
service keystone restart
echo "SETUP KEYSTONE.... ########"
sleep 2

echo "CREATE ADMIN TENANT ########"
keystone $keystone_creds tenant-create --name=admin --description="Admin Tenant"
tenant_admin_id=`keystone $keystone_creds tenant-list |grep admin |awk '{print $2}'`
echo "CREATE SERVICE TENANT ########"
keystone $keystone_creds tenant-create --name=service --description="Service Tenant"
echo "CREATE ADMIN USER ########"
keystone $keystone_creds user-create --name=admin --pass=$admin_pass --email=clement@example.com
admin_user_id=`keystone $keystone_creds user-list |grep admin |awk '{print $2}'`
echo "CREATE ADMIN ROLE ########"
keystone $keystone_creds role-create --name=admin
echo "ASSIGN ADMIN USER TO ADMIN ROLE ########"
keystone $keystone_creds user-role-add --user=admin --tenant=admin --role=admin

echo "SETUP KEYSTONE SERVICE FOR KEYSTONE ########"
keystone_id=`keystone $keystone_creds service-create --name=keystone --type=identity --description="Keystone Identity Service" |grep -w id |awk '{print $4}'`
echo "SETUP KEYSTONE ENDPOINT ########"
keystone $keystone_creds endpoint-create --service-id=$keystone_id --publicurl=http://$ip:5000/v2.0 --internalurl=http://$ip:5000/v2.0 --adminurl=http://$ip:35357/v2.0
keystone $keystone_creds user-list
echo "KEYSTONE CONFIGURATION DONE! ########"
echo ""

echo "GLANCE INSTALL ########"
sleep 2
apt-get -y install glance
glance_conf=( /etc/glance/glance-api.conf /etc/glance/glance-registry.conf )
glance_paste=( /etc/glance/glance-api-paste.ini /etc/glance/glance-registry-paste.ini )

for i in "${glance_conf[@]}"
do
sed -i s,'sql_connection = sqlite:////var/lib/glance/glance.sqlite',"sql_connection = mysql://glance:$glance_password@$ip/glance",g $i
sed -i s,'auth_host = 127.0.0.1',"auth_host = $ip",g $i
sed -i s,%SERVICE_TENANT_NAME%,service,g $i
sed -i s,%SERVICE_USER%,glance,g $i
sed -i s,%SERVICE_PASSWORD%,$glance_password,g $i
done

echo "GLANCE DB_SYNC ########"
glance-manage db_sync
echo "CREATE GLANCE USER IN KEYSTONE ########"
keystone $keystone_creds user-create --name=glance --pass=$glance_password --email=glance@example.com
echo "ADD ROLE ADMIN TO GLANCE USER ########"
keystone $keystone_creds user-role-add --user=glance --tenant=service --role=admin

for i in "${glance_paste[@]}"
do
sed -i 's/\[filter:authtoken\]//g' $i
sed -i s,'paste.filter_factory = keystoneclient.middleware.auth_token:filter_factory',,g $i
sed -i s,'delay_auth_decision = true',,g $i
echo "[filter:authtoken]
paste.filter_factory=keystoneclient.middleware.auth_token:filter_factory
auth_host=$ip
admin_user=glance
admin_tenant_name=service
admin_password=$glance_password" >> $i
done

echo "SETUP GLANCE SERVICE FOR KEYSTONE ########"
glance_id=`keystone $keystone_creds service-create --name=glance --type=image --description="Glance Image Service" |grep -w id |awk '{print $4}'`
echo "SETUP GLANCE ENDPOINT ########"
keystone $keystone_creds endpoint-create --service-id=$glance_id --publicurl=http://$ip:9292 --internalurl=http://$ip:9292 --adminurl=http://$ip:9292
echo "RESTART GLANCE-API AND REGISTRY SERVICES... ########"
service glance-registry restart
service glance-api restart

echo "ADD ENVIRONMENT VARIABLES ########"
echo "export OS_USERNAME=admin" >> /etc/environment
echo "export OS_PASSWORD=$admin_pass" >> /etc/environment
echo "export OS_TENANT_NAME=admin" >> /etc/environment
echo "export OS_AUTH_URL=http://$ip:35357/v2.0" >> /etc/environment
echo "export OS_SERVICE_ENDPOINT=http://$ip:35357/v2.0" >> /etc/environment
echo "export OS_SERVICE_TOKEN=$token" >> /etc/environment
source /etc/environment

echo "ADD CIRROS TO GLANCE ########"
curl -O http://cdn.download.cirros-cloud.net/0.3.1/cirros-0.3.1-x86_64-disk.img
glance image-create --name="CirrOS 0.3.1" --disk-format=qcow2 --container-format=bare --is-public=true < cirros-0.3.1-x86_64-disk.img
glance --os-username=admin --os-password=$admin_pass --os-tenant-name=admin --os-auth-url=http://$ip:35357/v2.0 image-list
echo "GLANCE CONFIGURATION DONE! ########"
echo ""

echo "EUCA2OOLS SETUP ########"
sleep 2
echo "SETUP EC2 SERVICE FOR KEYSTONE ########"
euca2ool_id=`keystone $keystone_creds  service-create --name=ec2 --type=ec2 --description="EC2 Compatibility Layer" |grep -w id |awk '{print $4}'`
echo "SETUP EC2 ENDPOINT ########"
keystone $keystone_creds endpoint-create --service-id=$euca2ool_id --publicurl=http://$ip:8773/services/Cloud --internalurl=http://$ip:8773/services/Cloud --adminurl=http://$ip:8773/services/Admin
echo "GENERATE EC2 KEYS ########"
keystone $keystone_creds ec2-credentials-create --user_id $admin_user_id --tenant_id $tenant_admin_id
access_id=`keystone $keystone_creds ec2-credentials-list --user_id $admin_user_id |grep -v WARNING |grep -v \+ | awk '{print $4}' |grep -v access`
secret_id=`keystone $keystone_creds ec2-credentials-list --user_id $admin_user_id |grep -v WARNING |grep -v \+ | awk '{print $6}' |grep -v secret`
echo "EC2_ACCESS_KEY=$access_id" >> /etc/environment
echo "EC2_SECRET_KEY=$secret_id" >> /etc/environment
echo "EC2_URL=http://127.0.0.1:8773/services/Cloud" >> /etc/environment
echo "EUCA2OOLS CONFIGURATION DONE! ########"
echo ""

echo "NOVA INSTALL ########"
sleep 2

apt-get -y install nova-novncproxy novnc nova-api nova-ajax-console-proxy nova-cert nova-conductor nova-consoleauth nova-doc nova-scheduler python-novaclient
nova-manage db sync
echo "CREATE NOVA USER IN KEYSTONE ########"
keystone $keystone_creds user-create --name=nova --pass=$nova_password --email=nova@example.com
echo "ADD ROLE ADMIN TO NOVA USER ########"
keystone $keystone_creds user-role-add --user=nova --tenant=service --role=admin

sed -i s,'auth_host = 127.0.0.1',"auth_host = $ip",g /etc/nova/api-paste.ini
sed -i s,%SERVICE_TENANT_NAME%,service,g /etc/nova/api-paste.ini
sed -i s,%SERVICE_USER%,nova,g /etc/nova/api-paste.ini
sed -i s,%SERVICE_PASSWORD%,$nova_password,g /etc/nova/api-paste.ini

echo "SETUP NOVA SERVICE FOR KEYSTONE ########"
nova_id=`keystone $keystone_creds service-create --name=nova --type=compute --description="Nova Compute Service" |grep -w id |awk '{print $4}'`
echo "SETUP NOVA ENDPOINT ########"
keystone $keystone_creds endpoint-create --service-id=$nova_id --publicurl=http://$ip:8774/v2/%\(tenant_id\)s --internalurl=http://$ip:8774/v2/%\(tenant_id\)s --adminurl=http://$ip:8774/v2/%\(tenant_id\)s
echo "my_ip=$ip
auth_strategy=keystone
rpc_backend = nova.rpc.impl_kombu
rabbit_host = $ip
#VNC
novnc_enabled=true
novncproxy_base_url=http://127.0.0.1:6080/vnc_auto.html
novncproxy_port=6080
vncserver_proxyclient_address=127.0.0.1
vncserver_listen=0.0.0.0
# GLANCE
image_service=nova.image.glance.GlanceImageService
glance_api_servers=$ip:9292
[database]
connection = mysql://nova:$nova_password@$ip/nova" >> /etc/nova/nova.conf
echo "MIGRATE NOVA DB ########"
nova-manage db sync
echo "RESTART NOVA SERVICES... ########"
service nova-api restart; service nova-cert restart; service nova-consoleauth restart; service nova-scheduler restart; service nova-conductor restart; service nova-novncproxy restart
echo "WAITING FOR THE NOVA SERVICES TO RESTART... ########"
sleep 3
nova --os-username=admin --os-password=$admin_pass --os-tenant-name=admin --os-auth-url=http://$ip:35357/v2.0 image-list

echo "NOVA CONFIGURATION DONE! ########"
echo ""

echo "CINDER INSTALL ########"
sleep 2
apt-get -y install cinder-api cinder-scheduler
echo "[database]
connection = mysql://cinder:$cinder_password@$ip/cinder" >> /etc/cinder/cinder.conf
echo "CINDER DB_SYNC ########"
cinder-manage db sync
echo "CREATE CINDER USER IN KEYSTONE ########"
keystone $keystone_creds user-create --name=cinder --pass=$cinder_password --email=cinder@example.com
echo "ADD ROLE ADMIN TO CINDER USER ########"
keystone $keystone_creds user-role-add --user=cinder --tenant=service --role=admin
sed -i s,'auth_host = 127.0.0.1',"auth_host = $ip",g /etc/cinder/api-paste.ini
sed -i s,%SERVICE_TENANT_NAME%,service,g /etc/cinder/api-paste.ini
sed -i s,%SERVICE_USER%,cinder,g /etc/cinder/api-paste.ini
sed -i s,%SERVICE_PASSWORD%,$cinder_password,g /etc/cinder/api-paste.ini

echo "SETUP CINDER SERVICE API V1 FOR KEYSTONE ########"
cinder_id=`keystone $keystone_creds service-create --name=cinder --type=volume --description="Cinder Volume Service" |grep -w id |awk '{print $4}'`
echo "SETUP CINDER API V1 ENDPOINT ########"
keystone $keystone_creds endpoint-create --service-id=$cinder_id --publicurl=http://$ip:8776/v1/%\(tenant_id\)s --internalurl=http://$ip:8776/v1/%\(tenant_id\)s --adminurl=http://$ip:8776/v1/%\(tenant_id\)s
echo "SETUP CINDER SERVICE API V2 FOR KEYSTONE ########"
cinder_id2=`keystone $keystone_creds service-create --name=cinder --type=volume2 --description="Cinder Volume Service V2" |grep -w id |awk '{print $4}'`
echo "SETUP CINDER API V2 ENDPOINT ########"
keystone $keystone_creds endpoint-create --service-id=$cinder_id2 --publicurl=http://$ip:8776/v2/%\(tenant_id\)s --internalurl=http://$ip:8776/v2/%\(tenant_id\)s --adminurl=http://$ip:8776/v2/%\(tenant_id\)s
echo "RESTART CINDER-API AND REGISTRY SERVICES... ########"
service cinder-scheduler restart
service cinder-api restart

echo "CINDER CONFIGURATION DONE! ########"
echo ""

echo "DASHBOARD INSTALL ########"
apt-get -y install memcached libapache2-mod-wsgi openstack-dashboard
apt-get -y remove --purge openstack-dashboard-ubuntu-theme
sed -i "s/OPENSTACK_HOST = \"127.0.0.1\"/OPENSTACK_HOST = \"$ip\"/g" /etc/openstack-dashboard/local_settings.py

echo ""
echo "Done! ########"
echo "You can access Horizon here: http://$ip/horizon"
echo "User: admin / Password: $admin_pass"
echo "This script took $SECONDS seconds to finish!"
echo "########"
