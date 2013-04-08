#
# Cookbook Name:: oat
# Recipe:: client
#
#

#NOTE: assumed that server exists
oat_server =( search(:node, "roles:oat-server") || [] ).first

package "trousers"

service "trousers" do
  supports :status => true, :restart => true
  action [:enable, :start]
end

#apply fix
execute "remove_chuid_from_trousers" do
  command "sed -i 's/--chuid \${USER}//g' /etc/init.d/trousers"
  only_if "grep -q chuid /etc/init.d/trousers"
  notifies :restart, "service[trousers]", :immediately
end

[ { "k" => "endorsement-password", "t" => "password", "v" => oat_server[:oat][:password] },
  { "k" => "hostname", "t" => "string", "v" => oat_server[:fqdn] },
].each { |x|
  execute "set_#{x['k']}_for_oat-client-installation" do
    command "echo oat-client oat-client/#{x['k']} #{x['t']} #{x['v']} | debconf-set-selections"
    not_if { File.exists? '/etc/oat-client' }
  end
}

ENV['DEBIAN_FRONTEND'] = 'noninteractive'
package "oat-client" do
  options "--force-yes"
end

service "oat-client" do
  supports :status => true, :restart => true
  action [:enable, :start]
end 

