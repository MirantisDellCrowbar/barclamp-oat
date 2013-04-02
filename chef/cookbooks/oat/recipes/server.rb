#
# Cookbook Name:: oat
# Recipe:: server
#
#

::Chef::Recipe.send(:include, Opscode::OpenSSL::Password)

node.set_unless['oat']['db']['password'] = secure_password

Chef::Log.info("Configuring OAT to use MySQL backend")

include_recipe "mysql::client"

env_filter = " AND mysql_config_environment:mysql-config-#{node[:oat][:mysql_instance]}"
mysqls = search(:node, "roles:mysql-server#{env_filter}") || []
if mysqls.length > 0
    mysql = mysqls[0]
    mysql = node if mysql.name == node.name
else
    mysql = node
end

mysql_address = Chef::Recipe::Barclamp::Inventory.get_network_by_type(mysql, "admin").address if mysql_address.nil?
Chef::Log.info("Mysql server found at #{mysql_address}")

mysql_database "create #{node[:oat][:db][:database]} oat database" do
    host    mysql_address
    username "db_maker"
    password mysql[:mysql][:db_maker_password]
    database node[:oat][:db][:database]
    action :create_db
end

mysql_database "create oat database user #{node[:oat][:db][:user]}" do
    host    mysql_address
    username "db_maker"
    password mysql[:mysql][:db_maker_password]
    database node[:oat][:db][:database]
    action :query
    sql "GRANT SELECT, INSERT, UPDATE, DELETE, CREATE, DROP, INDEX, ALTER on #{node[:oat][:db][:database]}.* to '#{node[:oat][:db][:user]}'@'%' IDENTIFIED BY '#{node[:oat][:db][:password]}';"
end

template "/etc/dbconfig-common/oat-appraiser.conf" do
  source "oat-appraiser.conf.erb"
  variables(:db_user => node[:oat][:db][:user],
            :db_pass => node[:oat][:db][:password],
            :db_name => node[:oat][:db][:database]
           )
end

ENV['DB_CONFIGURED'] = 'true'
ENV['DEBIAN_FRONTEND'] = 'noninteractive'
package "oat-appraiser" do
  options "--force-yes"
end

execute "restart_tomcat6_service" do
  command "invoke-rc.d tomcat6 restart"
  ignore_failure true
  action :nothing
end

execute "restart_apache2_service" do
  command "invoke-rc.d apache2 restart"
  ignore_failure true
  action :nothing
end

execute "fix_db_hostname" do
  command "find /etc/oat-appraiser -type f -exec sed -i 's/localhost/#{mysql_address}/' {} \\;"
  only_if "grep -q -r localhost /etc/oat-appraiser/"
  ignore_failure true
  notifies :run, resources(:execute => "restart_tomcat6_service")
  notifies :run, resources(:execute => "restart_apache2_service")
end

