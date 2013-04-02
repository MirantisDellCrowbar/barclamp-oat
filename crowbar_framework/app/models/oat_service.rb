# Copyright 2013, Mirantis 
# 
# Licensed under the Apache License, Version 2.0 (the "License"); 
# you may not use this file except in compliance with the License. 
# You may obtain a copy of the License at 
# 
#  http://www.apache.org/licenses/LICENSE-2.0 
# 
# Unless required by applicable law or agreed to in writing, software 
# distributed under the License is distributed on an "AS IS" BASIS, 
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. 
# See the License for the specific language governing permissions and 
# limitations under the License. 
# 

class OatService < ServiceObject

  def initialize(thelogger)
    @bc_name = "oat"
    @logger = thelogger
  end

  def proposal_dependencies(role)
    answer = []
    answer << { "barclamp" => "mysql", "inst" => role.default_attributes["oat"]["mysql_instance"] }
    answer
  end
  
  #if barclamp allows multiple proposals OVERRIDE
  # def self.allow_multiple_proposals?
  
  def create_proposal
    @logger.debug("Oat create_proposal: entering")
    base = super

    nodes = NodeObject.all
    nodes.delete_if { |n| n.nil? or n.admin? }
    if nodes.size >= 1
      base["deployment"]["oat"]["elements"] = {
        "oat-server" => [ nodes.first[:fqdn] ]
      }
    end

    base["attributes"]["oat"]["mysql_instance"] = ""
    begin
      mysqlService = MysqlService.new(@logger)
      # Look for active roles
      mysqls = mysqlService.list_active[1]
      if mysqls.empty?
        # No actives, look for proposals
        mysqls = mysqlService.proposals[1]
      end
      base["attributes"]["oat"]["mysql_instance"] = mysqls[0] unless mysqls.empty?
    rescue
      @logger.info("Oat create_proposal: no mysql found")
    end
    

    @logger.debug("Oat create_proposal: exiting")
    base
  end

  def apply_role_pre_chef_call(old_role, role, all_nodes)
    @logger.debug("Oat apply_role_pre_chef_call: entering #{all_nodes.inspect}")
    return if all_nodes.empty?

    om = old_role ? old_role.default_attributes["oat"] : {}
    nm = role.default_attributes["oat"]
    begin
      if om["db"]["password"]
        nm["db"]["password"] = om["db"]["password"]
      else
        nm["db"]["password"] = random_password
      end
    rescue
      nm["db"]["password"] = random_password
    end
    role.save 
    @logger.debug("Oat apply_role_pre_chef_call: leaving")
  end

end

