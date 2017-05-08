# aws-account-setup
Scripts and config files for setup of a standard AWS account. Implements auditing and configuration as described in [Standard AWS Account Configurations](https://confluence.cornell.edu/display/CLOUD/Standard+AWS+Account+Configurations).

## 1. Setup your SAML Identity Provider Metadata

Replace [templates/shibidp-md.xml](templates/shibidp-md.xml) with your SAML Identity Provider Metadata. See http://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_providers_saml_3rd-party.html. Once you set this up, you will be able to reuse it for setting up multiple AWS accounts that are supposed to use the same identity provider.


## 2. onboard.yml

Edit the following parameters in this YAML file - as needed - to reflect the account being configured:

* **profile** - The pre-configured AWS CLI profile name an AWS Access Key / Secret Key combo for the account to be onboarded
* **region** - The AWS region to use for single-region resources, e.g. VPC, ConfigService Rules, etc.
* **account_moniker** - The client moniker (e.g., in the form school-department)
* **account_number** - The 12 digit AWS account number

* **shib_saml_provider** - The name for the SAML provider to create / use in IAM (default: my_idp)
* **shib_role_name** - The name of the IAM Role that will be linked with the ActiveDirectory group (default: shib-admin)
* **shib_role_policy** - The ARN of the policy to attach to the Shib IAM role (default: AdministratorAccess)
* **cs_role_name** - The name of the IAM Role for the Cloud Services Role (default: shib-readonly)
* **cs_role_policy** - The ARN of the policy for the Cloud Services Role (default: ReadOnlyAccess)

* **configservice_iam_role_name** -  The prefix of the IAM role for ConfigService that will be created for each region.
* **configservice_s3_bucket_name** - The global S3 bucket prefix that will store ConfigService logs for all regions.
* **configservice_sns_topic_name** - The SNS topic name that will be created in every region and used to broadcast ConfigService changes.
* **itso_cloudtrail_bucket** - The protected name of the Security Office CloudTrail S3 Bucket

* **on_premise_cidr** - The CIDR that will be configured for Direct Connect / VPN tunnel
* **vpc_cidr** - The CIDR that will encompass the whole VPC network space
* **vpn_address** - The IP address of the optional VPN endpoint (Set to NULL when no VPN will be configured)
* **public_subnets** - The CIDR's and AZ's for each subnet configured with an Internet Gateway
* **private_subnets** - The CIDR's and AZ's for each subnet configured with a NAT Gateway (requires 1 public subnet)
* **nacls** - The ingress / egress NACL's that will be configured for every subnet.

## 3. go.sh

### Using go.sh

1. Edit the `onboard.yml` file to reflect the information for the AWS account being onboarded.
2. Ensure that needed dependencies are installed to your environment:
  - `gem install aws-sdk`
  - `pip install pyyaml`
    - Some folks may have better luck with `pip install --user pyyaml`
    - to upgrade to latest version `pip install --upgrade --user pyyaml`
  - `pip install troposphere`
    - Some folks may have better luck with `pip install --user troposphere`
    - to ugprade to latest verison `pip install --upgrade --user troposhere`
3. execute `go.sh`
  `$ ./go.sh`

### What does go.sh do?

- **go.sh** simply iterates through the `scripts` directory, giving the option to skip individual scripts.
- **shib.rb** will check for existing SAML provider / Shibboleth IAM Role listed in `onboard.yml` and create them if they don't exist. It will also set the account alias to match the account moniker and add apply a default IAM password policy if no existing password policy is found.
- **cloudformation.py** will generate Auditing and VPC templates from the configuration provided in `onboard.yml`.   
- **The auditing template** will enable CloudTrail in all regions, configure a ConfigService rule for `cloudtrail-enabled`, and their respective delivery settings to local and ITSO buckets. It will also create the CloudCheckr user for Princess.
- **The VPC template** will create a new VPC, VPG, IGW, Specified Subnets and Route Tables, Specified NACLs, NAT Gateway, and optional VPN connection.
- **The go script will ask whether to apply each template (audit and vpc) individually, but only if you created them in the previous step.**
- **config.rb** will check for existing ConfigService delivery to S3 and SNS in every region and create them if they don't exist.
- **nacls.rb** will NUKE the existing NACLs from all default NACL groups and reset them to a standard set of rules. Non-default NACL groups will be unaffected (such as those created with CloudFormation).
