#
# Cookbook Name:: oat
# Recipe:: client
#
#

#NOTE: assumed that server exists
oat-server =( search(:node, "roles:oat-server") || [] ).first

[ { "k": "endorsement-password", "t": "password", "v": oat-server[:oat][:password] },
  { "k": "hostname", "t": "string", "v": oat-server[:fqdn] },
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

