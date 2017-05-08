#!/usr/bin/env ruby

require 'aws-sdk'
require 'yaml'

@config = YAML.load(IO.read('onboard.yml'))

Aws.config.update({
  region: @config['region'],
  credentials: Aws::SharedCredentials.new(profile_name: @config['profile'])
})

@ec2  = Aws::EC2::Client.new
regions = @ec2.describe_regions({})

regions.regions.each do |region|
  puts region.region_name
  Aws.config[:region] = region.region_name
  @ec2 = Aws::EC2::Client.new

  nacls = @ec2.describe_network_acls({})

  nacls.network_acls.each do |acl|
    # Find default ACL
    if acl.is_default
      # Find all current entries and delete them
      acl.entries.each do |entry|
        if entry.rule_number < 32767
          resp = @ec2.delete_network_acl_entry({
            network_acl_id: acl.network_acl_id,
            rule_number: entry.rule_number,
            egress: entry.egress,
          })
        end
      end

      # Create port mappings for those listed in onboard.yml
      @rule_number = 0
      @config['nacls'].each do |nacl|
        @rule_number += 100

        [true, false].each do |egress|
          response = @ec2.create_network_acl_entry({
            network_acl_id: acl.network_acl_id,
            rule_number: @rule_number,
            protocol: nacl['protocol'].to_s,
            rule_action: nacl['rule'],
            egress: egress,
            cidr_block: nacl['cidr'],
            port_range: { 
              from: nacl['from'], 
              to: nacl['to'],
            },
          })
        
        end
      end
    end
  end
end
