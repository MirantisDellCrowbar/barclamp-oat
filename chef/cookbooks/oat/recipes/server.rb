#
# Cookbook Name:: glance
# Recipe:: api
#
#

include_recipe "#{@cookbook_name}::common"


package "oat-appraiser" do
  options "--force-yes"
  action :install
end


#oat_service "api"

node[:oat][:monitor][:svcs] <<["oat-api"]

