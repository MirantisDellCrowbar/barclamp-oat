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

#install agent from remote oatapp
#currently oat agent consists of a lot hardcoded path and so on, hope sometime oat will be properly packaged and released, but currently we have to install it in that way
if node[:oat][:owner_auth]=""
  node[:oat][:owner_auth]=(40.times.map{ rand(10) }).join
end

source=oat_server[:fqdn]
dist_name="ClientInstallForLinux.zip"
contain="ClientInstallForLinux"
clientpath="/usr/lib/OATClient"
execute "install-agent" do
  cwd "/tmp/"
  command <<-EOF
    wget http://#{source}/#{dist_name}
    unzip #{dist_name}
    cd #{contain}
    mkdir -p #{clientpath}
    cp OAT_Standalone.jar #{clientpath}/
    cp -r lib/ #{clientpath}/
    cp TrustStore.jks #{clientpath}/
    cp NIARL_TPM_Module #{clientpath}/
    touch #{clientpath}/log4j.properties
  EOF
  not_if { ::File.exists?("/etc/init.d/OATClient") }
end

template "/tmp/#{contain}/OAT.properties"
  source "OAT.properties.erb"
  variables (
    :source => source,
    :keyauth => #{node[:oat][:owner_auth]},
    :keyindex => 1
  )
end

template "/tmp/#{contain}/OATprovisioner.properties"
  source "OATprovisioner.properties.erb"
  variables (
    :keyauth => #{node[:oat][:owner_auth]},
    :keyindex => 1,
    :source => source,
    :clientpath => clientpath
  )
end


execute "provisioning_node" do
  cwd "/tmp/"
  command <<-EOF
    cd #{contain}
    #clear tpm creds
    ./NIARL_TPM_Module -mode 14 -owner_auth #{node[:oat][:owner_auth]} -cred_type EC
    #some copy-and-paste of perfect oat code with an awesome solution
    export provclasspath=".:./lib/activation.jar:./lib/axis.jar:./lib/bcprov-jdk15-141.jar:./lib/commons-discovery-0.2.jar:./lib/commons-logging-1.0.4.jar:./lib/FastInfoset.jar:./lib/HisPrivacyCAWebServices-client.jar:./lib/HisPrivacyCAWebServices2-client.jar:./lib/HisWebServices-client.jar:./lib/http.jar:./lib/jaxb-api.jar:./lib/jaxb-impl.jar:./lib/jaxb-xjc.jar:./lib/jaxrpc.jar:./lib/jaxws-api.jar:./lib/jaxws-rt.jar:./lib/jaxws-tools.jar:./lib/jsr173_api.jar:./lib/jsr181-api.jar:./lib/jsr250-api.jar:./lib/mail.jar:./lib/mimepull.jar:./lib/PrivacyCA.jar:./lib/resolver.jar:./lib/saaj-api.jar:./lib/saaj-impl.jar:./lib/SALlib_hibernate3.jar:./lib/stax-ex.jar:./lib/streambuffer.jar:./lib/TSSCoreService.jar:./lib/woodstox.jar:./lib/wsdl4j-1.5.1.jar"
    java -cp $provclasspath gov.niarl.his.privacyca.HisTpmProvisioner
    ret=$?
    if [ $ret == 0 ] ; then
      echo "Successfully initialized TPM"
    else
      echo "Failed to initialize the TPM, error $ret"
      exit 1
    fi
    
    
    java -cp $provclasspath gov.niarl.his.privacyca.HisIdentityProvisioner
    ret=$?
    if [ $ret == 0 ]; then
      echo "Successfully received AIC from Privacy CA" >> provisioning.log
    else
      echo "Failed to receive AIC from Privacy CA, error $ret" >> provisioning.log
      exit 1
    fi
    
    java -cp $provclasspath gov.niarl.his.privacyca.HisRegisterIdentity
    ret=$?
    if [ $ret == 0 ]; then
      echo "Successfully registered identity with appraiser" >> provisioning.log
    else
      echo "Failed to register identity with appraiser, error $ret" >> provisioning.log
      exit 1
    fi

  EOF
  not_if { ::File.exists?("/etc/init.d/OATClient") }
end

template "/etc/init.d/OATClient" do
  source "OATClient.erb"
  variables (
    :clientpath => clientpath
  )
end
