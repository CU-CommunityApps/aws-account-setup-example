#!/usr/bin/env ruby

require 'aws-sdk'
require 'yaml'

@config = YAML.load(File.read('onboard.yml'))

Aws.config.update({
  region: @config['region'],
  credentials: Aws::SharedCredentials.new(profile_name: @config['profile'])
})

@s3 = Aws::S3::Client.new
@iam = Aws::IAM::Client.new
@ec2 = Aws::EC2::Client.new
regions = @ec2.describe_regions({}).regions

  ###########################
  # ConfigService S3 Bucket #
  ###########################

begin
  config_bucket_name = @config['configservice_s3_bucket_name'] + "-#{@config['account_number']}"
  @s3.head_bucket({ bucket: config_bucket_name })
  puts "ConfigService: Using Existing S3 Bucket: #{config_bucket_name}"

  rescue Aws::S3::Errors::NotFound
    response = @s3.create_bucket({ bucket: config_bucket_name })
    if response.successful?
      puts "ConfigService: Created S3 Bucket: #{config_bucket_name}"
    else
      abort("ConfigService: Error Creating S3 Bucket: #{config_bucket_name}")
    end
end

regions.each do |region|
  puts "ConfigService: Setting up Region: #{region.region_name}"


  Aws.config[:region] = region.region_name
  @configservice = Aws::ConfigService::Client.new

  recorders = @configservice.describe_configuration_recorder_status({ }).configuration_recorders_status
  channels = @configservice.describe_delivery_channel_status({ }).delivery_channels_status

  # Check if ConfigService is already on for this region
  configservice_on = false
  if recorders.length > 0
    recorders.each do |recorder|
      if recorder.name == 'default' && recorder.recording && recorder.last_status == 'SUCCESS'
        channels.each do |channel|
          if channel.name == 'default' && channel.config_stream_delivery_info.last_status == 'SUCCESS'
            configservice_on = true
          end
        end
      end
    end
  end
  if configservice_on
    puts "ConfigService: Existing Config Settings Unchanged for Region: #{region.region_name}"
    next
  end

    ##################################
    # ConfigService Region SNS Topic #
    ##################################

  begin
    sns_topic_arn = "arn:aws:sns:#{region.region_name}:#{@config['account_number']}:#{@config['configservice_sns_topic_name']}"

    @sns = Aws::SNS::Client.new
    @sns.get_topic_attributes({ topic_arn: sns_topic_arn })
    puts "ConfigService: Using Existing SNS Topic: #{sns_topic_arn}"

    rescue Aws::SNS::Errors::NotFound
      response = @sns.create_topic({ name: @config['configservice_sns_topic_name'] })
      if response.successful?
        puts "ConfigService: Created SNS Topic: #{response.topic_arn}"
      else
        abort("ConfigService: Error Creating SNS Topic: #{sns_topic_arn}")
      end
  end

    #################################
    # ConfigService Region IAM Role #
    #################################

  begin
    config_role_name = @config['configservice_iam_role_name'] + "-#{region.region_name}"
    config_role_arn = "arn:aws:iam::#{@config['account_number']}:role/#{config_role_name}"

    role_policy = IO.read('./templates/configservice-role-policy.json')
    role_policy.gsub!('REGION', region.region_name)
    role_policy.gsub!('BUCKETNAME', config_bucket_name)
    role_policy.gsub!('ACCOUNTNUM', @config['account_number'])

    @iam.get_role({ role_name: config_role_name })
    puts "ConfigService: Using Existing IAM Role: #{config_role_name}"

    response = @iam.attach_role_policy({
      role_name: config_role_name,
      policy_arn: 'arn:aws:iam::aws:policy/service-role/AWSConfigRole' })
    if !response.successful?
      abort("ConfigService: Error Attaching AWSConfigRole Policy to IAM Role: #{config_role_name}")
    end

    response = @iam.put_role_policy({ role_name: config_role_name, policy_name: 'config-policy', policy_document: role_policy })
    if !response.successful?
      abort("ConfigService: Error Attaching Inline Policy to IAM Role: #{config_role_name}")
    end

    rescue Aws::IAM::Errors::NoSuchEntity
      assume_role_policy = IO.read('./templates/configservice-assume-role-policy.json')
      response = @iam.create_role({ role_name: config_role_name, assume_role_policy_document: assume_role_policy })

      if response.successful?
        puts "ConfigService: Created IAM Role: #{config_role_name}"
      else
        abort("ConfigService: Error Creating IAM Role: #{config_role_name}")
      end

      retry

  end

  # Wait for IAM Role to be available
  sleep 30

  #################################
  # ConfigService Region Recorder #
  #################################

  response = @configservice.put_configuration_recorder({
    configuration_recorder: {
      name: 'default',
      role_arn: config_role_arn,
      recording_group: {
        all_supported: true,
        include_global_resource_types: true,
      },
    },
  })

  if response.successful?
    puts "ConfigService: Created Configuration Recorder in Region: #{region.region_name}"
  else
    abort("ConfigService: Error Creating Configuration Recorder in Region: #{region.region_name}")
  end

  #########################################
  # ConfigService Region Delivery Channel #
  #########################################

  response = @configservice.put_delivery_channel({
    delivery_channel: {
      name: 'default',
      s3_bucket_name: config_bucket_name,
      sns_topic_arn: sns_topic_arn,
      config_snapshot_delivery_properties: {
        delivery_frequency: 'One_Hour',
      },
    },
  })

  if response.successful?
    puts "ConfigService: Created Delivery Channel for Region: #{region.region_name}"
  else
    abort("ConfigService: Error Creating Delivery Channel for Region: #{region.region_name}")
  end

  ##########################
  # Start Region Recording #
  ##########################

  response = @configservice.start_configuration_recorder({ configuration_recorder_name: 'default' })
  if response.successful?
    puts "ConfigService: Configuration Recorder Started for Region: #{region.region_name}"
  else
    abort("ConfigService: Error Starting Configuration Recorder for Region: #{region.region_name}")
  end

end
