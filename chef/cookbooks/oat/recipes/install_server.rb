#
# Cookbook Name:: oat
# Recipe:: server
#
#

::Chef::Recipe.send(:include, Opscode::OpenSSL::Password)

node.set_unless['oat']['db']['password'] = secure_password
node.set_unless['oat']['password'] = secure_password

# prepare db
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
    sql "FLUSH PRIVILEGES; GRANT ALL ON #{node[:oat][:db][:database]}.* to '#{node[:oat][:db][:user]}'@'%' IDENTIFIED BY '#{node[:oat][:db][:password]}';"
end

# installing package
# downloading it direclty because it can't be added to repository index
provisioners = search(:node, "roles:provisioner-server")
provisioner = provisioners[0] if provisioners
os_token="#{node[:platform]}-#{node[:platform_version]}"
repo_url = provisioner[:provisioner][:repositories][os_token][@cookbook_name].keys.first.split(' ')[1]

pkg_name = "OAT-Appraiser-Base-OATapp-1.0.0-2.x86_64.deb"
pkg_path = "/root/#{pkg_name}"
remote_file pkg_path do
  source "#{repo_url}/#{pkg_name}"
  action :create_if_missing
end

#NOTE: package unpacks itself into /OAT-Appraiser-Base/
dpkg_package pkg_name do
  source pkg_path
end

#create dirs
[ "/etc/oat-appraiser", "/var/lib/oat-appraiser", "/var/lib/oat-appraiser/ClientFiles",
  "/var/lib/oat-appraiser/CaCerts", "/var/lib/oat-appraiser/Certificate", "/usr/share/oat-appraiser"
].each { |d| directory d }

inst_name = "OAT-Appraiser-Base"

execute "unzip_OAT_Setup" do
  command "unzip /#{inst_name}/OAT_Server_Install.zip -d /#{inst_name}/"
  not_if { File.exists? "/#{inst_name}/oat_db.MySQL" } 
end

[ "oat_db.MySQL", "init.sql" ].each do |f|
  execute "create_tables_for_oat" do
    command "mysql -u #{node[:oat][:db][:user]} -p#{node[:oat][:db][:password]} -h #{mysql_address} #{node[:oat][:db][:database]} < /#{inst_name}/#{f}"
    ignore_failure true
    action :nothing
    subscribes :run, "execute[unzip_OAT_Setup]", :immediately
  end
end

#TODO: oatSetup.txt

#create keystore
execute "add_hostname_to_host" do
  command 'echo "127.0.0.1 `hostname`" >> /etc/hosts'
  not_if "grep `hostname` /etc/hosts"
end

node.set_unless[:oat][:keystore_pass] = secure_password
node.set_unless[:oat][:truststore_pass] = secure_password

bash "create_keystore_and_truststore" do
  cwd "/var/lib/oat-appraiser/Certificate"
  code <<-EOH
  openssl req -x509 -nodes -days 730 -newkey rsa:2048 -keyout hostname.pem -out hostname.cer -subj "/C=US/O=U.S. Government/OU=DoD/CN=`hostname`"
  openssl pkcs12 -export -in hostname.cer -inkey hostname.pem -out $p12file -passout pass:$p12pass
  keytool -importkeystore -srckeystore $p12file -destkeystore $keystore -srcstoretype pkcs12 -srcstorepass $p12pass -deststoretype jks -deststorepass $p12pass -noprompt
  myalias=`keytool -list -v -keystore $keystore -storepass $p12pass | grep -B2 'PrivateKeyEntry' | grep 'Alias name:'`
  keytool -changealias -alias ${myalias#*:} -destalias tomcat -v -keystore $keystore -storepass $p12pass
  rm -f $truststore
  keytool -import -keystore $truststore -storepass $truststore_pass -file hostname.cer -noprompt
  EOH
  environment {
    'p12pass' => node[:oat][:keystore_pass],
    'truststore_pass' => node[:oat][:truststore_pass],
    'p12file' => 'internal.p12',
    'keystore' => 'keystore.jks',
    'truststore' => 'truststore.jks', 
  }
  ignore_failure true
  not_if { File.exists? "/var/lib/oat-appraiser/Certificate/truststore.jks" }
end

# install and
# configure tomcat6
package "tomcat6"

[ "AttestationService",  "HisPrivacyCAWebServices2",
  "HisWebServices", "WLMService"].each do |webapp|
  template "/etc/oat-appraiser/#{webapp}.xml" do
    source "webapp.xml.erb"
    variables(
      :resource_name => webapp,
      :webapp_path => '/usr/share/oat-appraiser/webapps',
      :db_user => node[:oat][:db][:user],
      :db_pass => node[:oat][:db][:password],
      :db_name => node[:oat][:db][:database],
      :mysql_host => mysql_address
    )
  end
  execute "link_service_#{webapp}" do
    command "ln -sf /etc/oat-appraiser/#{webapp}.xml /etc/tomcat6/Catalina/localhost/"
    not_if { File.exists? "/etc/oat-appraiser/#{webapp}.xml" }
  end
end

template "/etc/oat-appraiser/server.xml" do
  source "server.xml.erb"
end

bash "deploy_server_xml" do
  code <<-EOH
  rm -f /etc/tomcat6/server.xml
  ln -sf /etc/oat-appraiser/server.xml /etc/tomcat6/server.xml
  EOH
  not_if { File.symlimk? "/etc/tomcat6/server.xml" }
end

bash "deploy_wars" do
  cwd "/#{inst_name}"
  code <<-EOH
  mkdir -p /usr/share/oat-appraiser/webapps/
  unzip /$name/OAT_Server_Install.zip -d /$name/
  cp -R /$name/OAT_Server_Install/HisWebServices $WEBAPP_DIR/
  
  cp /$name/OAT_Server_Install/WLMService.war $WEBAPP_DIRs/
  cp /$name/OAT_Server_Install/AttestationService.war $WEBAPP_DIR/
  cp /$name/HisPrivacyCAWebServices2.war $WEBAPP_DIR/
  mv $WEBAPP_DIR/AttestationService/WEB-INF/classes/OpenAttestationWebServices.properties /etc/oat-appraiser/OpenAttestationWebServices.properties
  #configuring hibernateHis for OAT appraiser setup
  cp /$name/OAT_Server_Install/hibernateOat.cfg.xml $WEBAPP_DIR/webapps/HisWebServices/WEB-INF/classes/
  mv $WEBAPP_DIR/webapps/HisWebServices/WEB-INF/classes/OpenAttestation.properties /etc/oat-appraiser/

EOH
  not_if { File.exists? "/usr/share/oat-appraiser/webapps/" }
end

