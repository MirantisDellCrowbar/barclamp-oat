#
# Cookbook Name:: oat
# Recipe:: server
#
#

::Chef::Recipe.send(:include, Opscode::OpenSSL::Password)

node.set_unless['oat']['db']['password'] = secure_password
node.set_unless['oat']['password'] = secure_password

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

cf = cookbook_file "/root/create_tables.sql" do
  source "create_tables.sql"
  action :nothing
end
cf.run_action(:create)

execute "create_tables_for_oat" do
  command "mysql -u #{node[:oat][:db][:user]} -p#{node[:oat][:db][:password]} -h #{mysql_address} #{node[:oat][:db][:database]} < /root/create_tables.sql"
  ignore_failure true
  action :nothing
end

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
    notifies :run, resources(:execute => "create_tables_for_oat"), :immediately
end

template "/etc/dbconfig-common/oat-appraiser.conf" do
  source "oat-appraiser.conf.erb"
  variables(:db_user => node[:oat][:db][:user],
            :db_pass => node[:oat][:db][:password],
            :db_name => node[:oat][:db][:database]
           )
end

[ { "k" => "password", "t" => "password", "v" => node[:oat][:password] },
  { "k" => "old-password", "t" => "password", "v" => node[:oat][:password] },
  { "k" => "hostname", "t" => "string", "v" => node[:fqdn] },
  { "k" => "old-hostname", "t" => "string", "v" => node[:fqdn] },
].each { |x|
  execute "set_#{x['k']}_for_oat-appraiser-installation" do
    command "echo oat-appraiser oat-appraiser/#{x['k']} #{x['t']} #{x['v']} | debconf-set-selections"
    not_if { File.exists? '/etc/oat-appraiser/server.xml' }
  end
}

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

