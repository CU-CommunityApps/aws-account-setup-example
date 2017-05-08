#!/usr/bin/env ruby

require 'aws-sdk'
require 'yaml'

@config = YAML.load(IO.read('onboard.yml'))

Aws.config.update({
  region: @config['region'],
  credentials: Aws::SharedCredentials.new(profile_name: @config['profile'])
})

@cfn = Aws::CloudFormation::Client.new

def applyTemplate(template_type)
    stack_name = "#{@config['account_moniker']}-#{template_type}"
    template = IO.read("./cloudformation/#{@config['account_moniker']}-#{template_type}.json")
    
    response = @cfn.create_stack({
      stack_name: stack_name,
      template_body: template,
      capabilities: ['CAPABILITY_IAM', 'CAPABILITY_NAMED_IAM'],
      on_failure: "DELETE",
    })

    if response.successful?
      puts "CFN Apply: Initiated #{stack_name} Stack Creation"
    else
      abort("CFN Apply: Error Initiating #{stack_name} Stack Creation")
    end

    begin
      puts "CFN Apply: Waiting for #{stack_name} Stack to Finish Creating..."
      response = @cfn.wait_until(:stack_create_complete, stack_name: stack_name)
      puts "CFN Apply: #{stack_name} Stack Created Successfully"
      
      rescue Aws::Waiters::Errors::WaiterFailed
        puts "CFN Apply: Error Creating #{stack_name} Stack. Waiting for Stack to Finish Deleting..."

        begin
          response = @cfn.wait_until(:stack_delete_complete, stack_name: stack_name)
          puts "CFN Apply: #{stack_name} Stack Deleted Successfully"
  
          rescue Aws::Waiters::Errors::WaiterFailed
            abort("CFN Apply: Error Deleting #{stack_name} Stack. See CFN Console for More Information")
        end
    end
end

if File.file?("./cloudformation/#{@config['account_moniker']}-audit.json")
  while true do
    puts "Do you want to apply the Auditing CloudFormation Template to this account? [y/n]"
    yn = gets.strip.downcase

    if yn == 'y'
      puts "CFN Apply: Applying Auditing CloudFormation Template"
      applyTemplate('audit')
      break
    elsif yn == 'n'
      puts "CFN Apply: Skipping Auditing CloudFormation Template"
      break
    else
      puts "Answer y/n"
    end
  end
else
  puts "CFN Apply: No Auditing CloudFormation Template Exists, continuing..."
end

if File.file?("./cloudformation/#{@config['account_moniker']}-vpc.json")
  while true do
    puts "Do you want to apply the VPC CloudFormation Template to this account? [y/n]"
    yn = gets.strip.downcase

    if yn == 'y'
      puts "CFN Apply: Applying VPC CloudFormation Template"
      applyTemplate('vpc')
      break
    elsif yn == 'n'
      puts "CFN Apply: Skipping VPC CloudFormation Template"
      break
    else
      puts "Answer y/n"
    end
  end
else
  puts "CFN Apply: No VPN CloudFormation Template Exists, continuing..."
end
