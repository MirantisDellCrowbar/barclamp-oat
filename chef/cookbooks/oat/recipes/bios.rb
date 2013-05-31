#some magic should be here wich able to configure bios and pass control to tboot.rb

tpm_active=%x{cat /sys/class/misc/tpm0/device/active}
tpm_enabled=%x{cat /sys/class/misc/tpm0/device/enabled}
if tpm_enabled!="1" and tpm_active!="1"
  package "wsmancli" do
    options "--force-yes"
  end

  ip = Chef::Recipe::Barclamp::Inventory.get_network_by_type(node, "bmc").address
  user = node["ipmi"]["bmc_user"] rescue "root"
  password = node["ipmi"]["bmc_password"] rescue "cr0wBar!"
  cert_f = "/tmp/cer-192.168.124.8.cer"


  bash "create_keystore_and_truststore" do
    cwd "tpm"
    code <<-EOH
    echo | openssl s_client -connect #{ip}:443 2>&1 | sed -ne '/-BEGIN CERTIFICATE-/,/-END CERTIFICATE-/p' >#{cert_f} 2>&1
    wsman invoke -a SetAttribute "http://schemas.dmtf.org/wbem/wscim/1/cim-schema/2/DCIM_BIOSService?SystemCreationClassName=DCIM_ComputerSystem,CreationClassName=DCIM_BIOSService,SystemName=DCIM:ComputerSystem,Name=DCIM:BIOSService" -h #{ip} -P 443 -u #{user} -p "#{password}" -c #{cert_f} -N root/dcim -v -o -j utf-8 -y basic -m 512 -V -k 'Target=BIOS.Setup.1-1' -k 'AttributeName=TpmSecurity' -k 'AttributeValue=OnPbm'
    wsman invoke -a SetAttribute "http://schemas.dmtf.org/wbem/wscim/1/cim-schema/2/DCIM_BIOSService?SystemCreationClassName=DCIM_ComputerSystem,CreationClassName=DCIM_BIOSService,SystemName=DCIM:ComputerSystem,Name=DCIM:BIOSService" -h #{ip} -P 443 -u #{user} -p "#{password}" -c #{cert_f} -N root/dcim -v -o -j utf-8 -y basic -m 512 -V -k 'Target=BIOS.Setup.1-1' -k 'AttributeName=TpmActivation' -k 'AttributeValue=Activate'
    wsman invoke -a SetAttribute "http://schemas.dmtf.org/wbem/wscim/1/cim-schema/2/DCIM_BIOSService?SystemCreationClassName=DCIM_ComputerSystem,CreationClassName=DCIM_BIOSService,SystemName=DCIM:ComputerSystem,Name=DCIM:BIOSService" -h #{ip} -P 443 -u #{user} -p "#{password}"  -c #{cert_f} -N root/dcim -v -o -j utf-8 -y basic -m 512 -V -k 'Target=BIOS.Setup.1-1' -k 'AttributeName=IntelTxt' -k 'AttributeValue=On'
    #wsman invoke -a CreateRebootJob "http://schemas.dmtf.org/wbem/wscim/1/cim-schema/2/root/dcim/DCIM_SoftwareInstallationService?CreationClassName=DCIM_SoftwareInstallationService,SystemCreationClassName=DCIM_ComputerSystem,SystemName=IDRAC:ID,Name=SoftwareUpdate" -h #{ip} -P 443 -u #{user} -p "#{password}"  -c #{cert_f} -N root/dcim -v -o -j utf-8 -y basic -m 512 -V -k 'Target=BIOS.Setup.1-1' -k 'RebootJobType=2'
    wsman invoke -a CreateTargetedConfigJob "http://schemas.dmtf.org/wbem/wscim/1/cim-schema/2/DCIM_BIOSService?SystemCreationClassName=DCIM_ComputerSystem,CreationClassName=DCIM_BIOSService,SystemName=DCIM:ComputerSystem,Name=DCIM:BIOSService" -h #{ip} -P 443 -u #{user} -p "#{password}"  -c #{cert_f} -N root/dcim -v -o -j utf-8 -y basic -m 512 -V -k 'Target=BIOS.Setup.1-1' -k 'RebootJobType=2' -k 'ScheduledStartTime=TIME_NOW'
    EOH
  end

  require 'chef'
  require 'chef/handler'
  class RebootNode < Chef::Handler
    def initialize(options = {})
    end
    def report
      if run_status.success?
        Chef::Log.warn ">>> Reboot called"
        system "sync; sync; reboot"
      else
        Chef::Log.warn ">>> Reboot missed"
      end
    end
  end

  Chef::Config.report_handlers << RebootNode.new
end
