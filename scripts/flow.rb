#!/usr/bin/env ruby

require 'aws-sdk'
require 'yaml'

@config = YAML.load(IO.read('onboard.yml'))

Aws.config.update({
  region: @config['region'],
  credentials: Aws::SharedCredentials.new(profile_name: @config['profile'])
})

@ec2 = Aws::EC2::Client.new
@iam = Aws::IAM::Client.new

  ######################
  # Log Group IAM Role #
  ######################

begin
  flow_role_arn  = "arn:aws:iam::#{@config['account_number']}:role/#{@config['flow_iam_role_name']}"
    
  role_policy = IO.read('./templates/flow-role-policy.json')
  @iam.get_role({ role_name: @config['flow_iam_role_name'] })
  puts "FlowLogs: Using Existing IAM Role: #{@config['flow_iam_role_name']}"

  response = @iam.put_role_policy({ role_name: @config['flow_iam_role_name'], policy_name: 'flow-policy', policy_document: role_policy })
  if !response.successful?
    abort("FlowLogs: Error Attaching Inline Policy to IAM Role: #{@config['flow_iam_role_name']}")
  end

  rescue Aws::IAM::Errors::NoSuchEntity
    assume_role_policy = IO.read('./templates/flow-assume-role-policy.json')
    response = @iam.create_role({ role_name: @config['flow_iam_role_name'], assume_role_policy_document: assume_role_policy })

    if response.successful?
      puts "FlowLogs: Created IAM Role: #{@config['flow_iam_role_name']}"
      sleep 30 # Wait for IAM Role
    else
      abort("FlowLogs: Error Creating IAM Role: #{@config['flow_iam_role_name']}")
    end

    response = @iam.put_role_policy({ role_name: @config['flow_iam_role_name'], policy_name: 'flow-policy', policy_document: role_policy })
    if !response.successful?
      abort("FlowLogs: Error Attaching Inline Policy to IAM Role: #{@config['flow_iam_role_name']}")
    end
end

regions = @ec2.describe_regions({}).regions

regions.each do |region|
  puts "FlowLogs: Setting up Region #{region.region_name}"

  Aws.config[:region] = region.region_name
  @logs = Aws::CloudWatchLogs::Client.new
  @ec2 = Aws::EC2::Client.new

  ########################
  # CloudWatch Log Group #
  ########################

  log_group = "#{@config['account_moniker']}-flowlogs"
  response = @logs.describe_log_groups({ log_group_name_prefix: log_group })

  if response.log_groups.size == 0
    response = @logs.create_log_group({ log_group_name: log_group  })
    if response.successful?
      puts "FlowLogs: Created new log group: #{log_group}"
      sleep 30 # Wait for log group
    else
      abort("FlowLogs: Error creating log group: #{log_group}")
    end
  else
    puts "FlowLogs: Using existing log group: #{log_group}"
  end
  
  ########
  # VPCs #
  ########

  response = @ec2.describe_vpcs({})

  if response.successful?
    vpcs = response.vpcs
  else
    abort("FlowLogs: Error Describing VPC's in Region: #{region.region_name}")
  end

  response = @ec2.describe_flow_logs({})

  if response.successful?
    flow_logs = response.flow_logs
  else
    abort("FlowLogs: Error Describing Flow Logs in Region: #{region.region_name}")
  end

  vpcs.each do |vpc|
    flow_exists = false

    flow_logs.each do |flow_log|
      if flow_log.resource_id == vpc.vpc_id
        flow_exists = true
        break
      end
    end

    if flow_exists
      puts "FlowLogs: Existing Flow Log Unchanged for VPC: #{vpc.vpc_id}"
      next
    end

    response = @ec2.create_flow_logs({
      resource_ids:   [vpc.vpc_id],
      resource_type:  'VPC',
      traffic_type:   'ALL',
      log_group_name: log_group,
      deliver_logs_permission_arn: flow_role_arn,
    })

    if response.successful?
      puts "FlowLogs: Created New Flow Log for VPC: #{vpc.vpc_id}"
    else
      abort("FlowLogs: Error Creating New Flow Log for VPC: #{vpc.vpc_id}")
    end
    
  end

end

