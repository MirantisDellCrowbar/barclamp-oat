#
# Cookbook Name:: oat
# Recipe:: client
#
#

include_recipe "#{@cookbook_name}::common"


package "oat-client" do
  options "--force-yes"
  action :install
end


#oat_service "api"

node[:oat][:monitor][:svcs] <<["oat-client"]

