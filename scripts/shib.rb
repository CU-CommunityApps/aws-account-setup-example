#!/usr/bin/env ruby

require 'aws-sdk'
require 'yaml'

def createShibRole(account_num, shib_role_name, shib_role_policy_arn)

  begin
    @iam.get_role({ role_name: shib_role_name })
    puts "Shib: Using Existing IAM Role: #{shib_role_name}"

    response = @iam.list_attached_role_policies({ role_name: shib_role_name })

    if !response.successful?
      abort("Shib: Error Listing Managed Policies for IAM Role: #{shib_role_name}")
    end

    policy_exists = false
    response.attached_policies.each do |policy|
      if policy.policy_arn == shib_role_policy_arn
        policy_exists = true
        break
      end
    end

    if policy_exists
      puts "Shib: Existing Settings Unchanged for IAM Role: #{shib_role_name}"
    else
      response = @iam.attach_role_policy({ role_name: shib_role_name, policy_arn: shib_role_policy_arn })
      if response.successful?
        puts "Shib: Attached New Policy to IAM Role: #{shib_role_name}"
      else
        abort("Shib: Error Attaching Policy to IAM Role: #{shib_role_name}")
      end
    end

    if !response.successful?
      abort("Shib: Error Attaching Managed Policy to Role: #{shib_role_name}")
    end

    rescue Aws::IAM::Errors::NoSuchEntity
      assume_role_policy = IO.read('./templates/shib-assume-role-policy.json')
      assume_role_policy.gsub!('ACCOUNTNUM', account_num)
      response = @iam.create_role({ role_name: shib_role_name, assume_role_policy_document: assume_role_policy })

      if response.successful?
        puts "Shib: Created New IAM Role: #{shib_role_name}"
      else
        abort("Shib: Error Creating IAM Role: #{shib_role_name}")
      end

      response = @iam.attach_role_policy({ role_name: shib_role_name, policy_arn: shib_role_policy_arn })

      if response.successful?
        puts "Shib: Attached New Policy to IAM Role: #{shib_role_name}"
      else
        abort("Shib: Error Attaching Policy to IAM Role: #{shib_role_name}")
      end
  end 

end

@config = YAML.load(IO.read('onboard.yml'))

Aws.config.update({
  region: @config['region'],
  credentials: Aws::SharedCredentials.new(profile_name: @config['profile'])
})

@iam = Aws::IAM::Client.new

  ################################
  # Shibboleth IAM SAML Provider #
  ################################

begin
  shib_saml_arn = "arn:aws:iam::#{@config['account_number']}:saml-provider/#{@config['shib_saml_provider']}"
  @iam.get_saml_provider({ saml_provider_arn: shib_saml_arn  })
  puts "Shib: Using Existing SAML Provider: #{@config['shib_saml_provider']}"

  rescue Aws::IAM::Errors::NoSuchEntity
    shib_saml_document = IO.read('templates/shibidp-md.xml')
    response = @iam.create_saml_provider({ name: @config['shib_saml_provider'],saml_metadata_document: shib_saml_document  })

    if response.successful?
      puts "Shib: Created SAML Provider: #{@config['shib_saml_provider']}"
    else
      abort("Shib: Error Creating SAML Provider: #{@config['shib_saml_provider']}")
    end
end

  ###################################
  # Shibboleth IAM AdminAccess Role #
  ###################################

  createShibRole(@config['account_number'], @config['shib_role_name'], @config['shib_role_policy'])

  ##########################
  # Shibboleth IAM CS Role #
  ##########################

  createShibRole(@config['account_number'], @config['cs_role_name'], @config['cs_role_policy'])

  #################
  # Account Alias #
  #################

begin
  response = @iam.list_account_aliases({})
  
  if !response.successful?
    abort("Shib: Error Listing Account Aliases")
  end

  alias_exists = false
  response.account_aliases.each do |account_alias|
    if account_alias == @config['account_moniker']
      alias_exists = true
      break
    end
  end

  if !alias_exists
    response = @iam.create_account_alias({ account_alias: @config['account_moniker'] })
    if response.successful?
      puts "Shib: Set Account Alias: #{@config['account_moniker']}"
    else
      abort("Shib: Error Setting Account Alias: #{@config['account_moniker']}")
    end
  end

end


  #######################
  # IAM Password Policy #
  #######################

begin
  response = nil
  begin
    response = @iam.get_account_password_policy({})
    unless !response.successful?
      puts "Shib: IAM policy exists for account.  No changes will be applied."
    end
  rescue Aws::IAM::Errors::NoSuchEntity
    puts "Shib: No IAM password policy found for account"
  end

  unless !response.nil? && response.successful?
    response = @iam.update_account_password_policy( @config['iam_passwd_policy'] )
    if response.successful?
      puts "Shib: Set IAM password policy"
    else
      abort("Shib: Error Setting password policy")
    end
  end
end
