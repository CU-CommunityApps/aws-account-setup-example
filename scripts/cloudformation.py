#!/usr/bin/env python

from __future__ import print_function
from sys import exit, stderr
import json

# Helpers
def warning(*objs):
    print('WARNING: ', *objs, file=stderr)

def error(*objs):
    print('ERROR: ', *objs, file=stderr)

try:
    from troposphere import GetAtt, Join, Ref, Tags, Template
    import troposphere.cloudtrail as ct
    import troposphere.config as aws_config
    import troposphere.ec2 as ec2
    import troposphere.iam as iam
    import troposphere.s3 as s3
    import troposphere.sns as sns
except ImportError:
    error('Python Troposphere module not installed. Try `pip install troposphere` or `easy_install troposphere` (preferrably in a virtual_env).')
    exit(1)

try:
    import yaml
except ImportError:
    error('Python PyYaml module is not installed. Try `pip install pyyaml` or `easy_install pyyaml` (preferrably in a virtual_env).')
    exit(1)

# Load YAML config
global config
with open('onboard.yml', 'r') as yml:
    config = yaml.load(yml)

  #####################
  # Auditing Template #
  #####################

t = Template()
t.add_version('2010-09-09')
t.add_description('Standard Auditing Requirements')

  ########################
  # CloudTrail S3 Bucket #
  ########################

cloudtrailBucketName = '{0}-cloud-trail'.format(config['account_moniker'])

cloudtrailBucket = t.add_resource(s3.Bucket(
  'cloudtrailBucket',
  BucketName=cloudtrailBucketName,
  Tags=Tags(
    Name=Join('-', [config['account_moniker'], 'bucket-cloudtrail'])
  ),
))

  ############################
  # CloudTrail Bucket Policy #
  ############################

with open('./templates/cloudformation-cloudtrail-policy.json', 'r') as policy_template:
    s3policy = policy_template.read()
    s3policy = json.loads(s3policy.replace('BUCKETNAME', cloudtrailBucketName).replace('ACCOUNTNUM', config['account_number']))

cloudtrailBucketPolicy = t.add_resource(s3.BucketPolicy(
  'cloudtrailBucketPolicy',
  Bucket=Ref(cloudtrailBucket),
  PolicyDocument=s3policy,
  DependsOn=['cloudtrailBucket'],
))

  ###################
  # Main CloudTrail #
  ###################

cloudtrailMainTrail = t.add_resource(ct.Trail(
  'cloudtrailMainTrail',
  IncludeGlobalServiceEvents=True,
  IsLogging=True,
  IsMultiRegionTrail=True,
  S3BucketName=cloudtrailBucketName,
  Tags=Tags(
    Name=Join('-', [config['account_moniker'], 'trail-main'])
  ),
  DependsOn=['cloudtrailBucket', 'cloudtrailBucketPolicy']
))

  ###################
  # ITSO CloudTrail #
  ###################

if config['itso_cloudtrail_bucket'] != None:
    cloudtrailItsoTrail = t.add_resource(ct.Trail(
      'cloudtrailItsoTrail',
      IncludeGlobalServiceEvents=True,
      IsLogging=True,
      IsMultiRegionTrail=True,
      S3BucketName=config['itso_cloudtrail_bucket'],
      Tags=Tags(
        Name=Join('-', [config['account_moniker'], 'trail-itso'])
      ),
    ))
else:
    warning('ITSO Trail was not added to the template because ITSO CloudTrail Bucket is not in the config.')

  ##############################
  # AWS Config CloudTrail Rule #
  ##############################

configSource = aws_config.Source(
  'configSource',
  Owner='AWS',
  SourceIdentifier='CLOUD_TRAIL_ENABLED',
)

configRule = t.add_resource(aws_config.ConfigRule(
  'configRule',
  ConfigRuleName='cloudtrail-enabled',
  Description='Checks whether AWS CloudTrail is enabled in your AWS account.',
  Source=configSource,
  MaximumExecutionFrequency='One_Hour',
))

with open('./cloudformation/{0}-audit.json'.format(config['account_moniker']), 'w') as tmpl:
    tmpl.write(t.to_json())









  ################
  # VPC Template #
  ################

t = Template()
t.add_version('2010-09-09')
t.add_description('A VPC environment in two availability zones with a NAT Gateway and optional VPN connection')

  #######
  # VPC #
  #######

vpc = t.add_resource(ec2.VPC(
  'vpc',
  CidrBlock=config['vpc_cidr'],
  InstanceTenancy='default',
  EnableDnsSupport='true',
  Tags=Tags(
    Name=Join('-', [config['account_moniker'], 'vpc'])
  ),
))

  ####################
  # Internet Gateway #
  ####################

igw = t.add_resource(ec2.InternetGateway(
  'igw',
  Tags=Tags(
    Name=Join('-', [config['account_moniker'], 'igw'])
  ),
))

  ###############################
  # Internet Gateway Attachment #
  ###############################

gatewayAttachment = t.add_resource(ec2.VPCGatewayAttachment(
  'gatewayAttachment',
  VpcId=Ref(vpc),
  InternetGatewayId=Ref(igw),
  DependsOn=['vpc', 'igw'],
))

  ###########################
  # Virtual Private Gateway #
  ###########################

vpg = t.add_resource(ec2.VPNGateway(
  'vpg',
  Type='ipsec.1',
  Tags=Tags(
    Name=Join('-', [config['account_moniker'], 'vpg']),
  ),
))

  ##################
  # VPG Attachment #
  ##################

vpgGatewayAttachment = t.add_resource(ec2.VPCGatewayAttachment(
  'vpgGatewayAttachment',
  VpcId=Ref(vpc),
  VpnGatewayId=Ref(vpg),
  DependsOn=['vpc', 'vpg'],
))

  ######################
  # Public Route Table #
  ######################

rtbPublic = t.add_resource(ec2.RouteTable(
  'rtbPublic',
  VpcId=Ref(vpc),
  Tags=Tags(
    Name=Join('-', [config['account_moniker'], 'public-rt']),
  ),
  DependsOn=['vpc'],
))

  #########################
  # Public Internet Route #
  #########################

routePublic = t.add_resource(ec2.Route(
  'routePublic',
  GatewayId=Ref(igw),
  DestinationCidrBlock='0.0.0.0/0',
  RouteTableId=Ref(rtbPublic),
  DependsOn=['gatewayAttachment', 'rtbPublic'],
))


  #########################
  # 10-Space Public Route #
  #########################

route10SpacePublic = t.add_resource(ec2.Route(
  'route10SpacePublic',
  GatewayId=Ref(vpg),
  DestinationCidrBlock='10.0.0.0/8',
  RouteTableId=Ref(rtbPublic),
  DependsOn['vpgGatewayAttachment', 'rtbPublic'],
))

  ##########################
  # NAT Gateway Elastic IP #
  ##########################

eip_nat_gateway = t.add_resource(ec2.EIP(
  'eipNatGateway',
  Domain='vpc'
))

  ###############
  # NAT Gateway #
  ###############

natGateway = t.add_resource(ec2.NatGateway(
  'natGateway',
  SubnetId=Ref('subnetPublic1'),
  AllocationId=GetAtt(eip_nat_gateway, 'AllocationId'),
  DependsOn=['subnetPublic1', 'eipNatGateway'],
))

  #######################
  # Private Route Table #
  #######################

rtbPrivate = t.add_resource(ec2.RouteTable(
  'rtbPrivate',
  VpcId=Ref(vpc),
  Tags=Tags(
    Name=Join('-', [config['account_moniker'], 'private-rt']),
  ),
  DependsOn=['vpc'],
))

  #####################
  # NAT Gateway Route #
  #####################

routePrivate = t.add_resource(ec2.Route(
  'routePrivate',
  NatGatewayId=Ref(natGateway),
  DestinationCidrBlock='0.0.0.0/0',
  RouteTableId=Ref(rtbPrivate),
  DependsOn=['natGateway', 'rtbPrivate'],
))

  ##########################
  # 10-Space Private Route #
  ##########################

route10SpacePrivate = t.add_resource(ec2.Route(
  'route10SpacePrivate',
  GatewayId=Ref(vpg),
  DestinationCidrBlock='10.0.0.0/8',
  RouteTableId=Ref(rtbPrivate),
  DependsOn=['vpgGatewayAttachment', 'rtbPrivate'],
))

  ##################################
  # CU Public-Space Private Routes #
  ##################################

routePub1Private = t.add_resource(ec2.Route(
  'routePub1Private',
  GatewayId=Ref(vpg),
  DestinationCidrBlock='128.84.0.0/16',
  RouteTableId=Ref(rtbPrivate),
  DependsOn=['vpgGatewayAttachment', 'rtbPrivate'],
))

routePub2Private = t.add_resource(ec2.Route(
  'routePub1Private',
  GatewayId=Ref(vpg),
  DestinationCidrBlock='128.253.0.0/16',
  RouteTableId=Ref(rtbPrivate),
  DependsOn=['vpgGatewayAttachment', 'rtbPrivate'],
))

routePub3Private = t.add_resource(ec2.Route(
  'routePub1Private',
  GatewayId=Ref(vpg),
  DestinationCidrBlock='132.236.0.0/16',
  RouteTableId=Ref(rtbPrivate),
  DependsOn=['vpgGatewayAttachment', 'rtbPrivate'],
))

routePub4Private = t.add_resource(ec2.Route(
  'routePub1Private',
  GatewayId=Ref(vpg),
  DestinationCidrBlock='192.35.82.0/24',
  RouteTableId=Ref(rtbPrivate),
  DependsOn=['vpgGatewayAttachment', 'rtbPrivate'],
))

routePub5Private = t.add_resource(ec2.Route(
  'routePub1Private',
  GatewayId=Ref(vpg),
  DestinationCidrBlock='192.122.235.0/24',
  RouteTableId=Ref(rtbPrivate),
  DependsOn=['vpgGatewayAttachment', 'rtbPrivate'],
))

routePub6Private = t.add_resource(ec2.Route(
  'routePub1Private',
  GatewayId=Ref(vpg),
  DestinationCidrBlock='192.122.236.0/24',
  RouteTableId=Ref(rtbPrivate),
  DependsOn=['vpgGatewayAttachment', 'rtbPrivate'],
))

  ##################
  # Public Subnets #
  ##################

publicSubnetNumber = 0
for subnet in config['public_subnets']:
    publicSubnetNumber += 1
    subnetName = 'subnetPublic' + str(publicSubnetNumber)

      #################
      # Public Subnet #
      #################

    subnetPublic = t.add_resource(ec2.Subnet(
      subnetName,
      VpcId=Ref(vpc),
      AvailabilityZone=config['region'] + subnet['az'],
      CidrBlock=subnet['cidr'],
      Tags=Tags(
        Name=Join('-', [config['account_moniker'], 'Subnet-Public', publicSubnetNumber]),
      ),
      DependsOn=['vpc']
    ))

      ############################
      # Public Route Association #
      ############################

    rtbAssociationPublic = t.add_resource(ec2.SubnetRouteTableAssociation(
      'rtbAssociationPublic' + str(publicSubnetNumber),
      SubnetId=Ref(subnetPublic),
      RouteTableId=Ref(rtbPublic),
      DependsOn=[subnetName, 'rtbPublic'],
    ))

  ###################
  # Private Subnets #
  ###################

privateSubnetNumber = 0
for subnet in config['private_subnets']:
    privateSubnetNumber += 1
    subnetName = 'subnetPrivate' + str(privateSubnetNumber)

      ##################
      # Private Subnet #
      ##################

    subnetPrivate = t.add_resource(ec2.Subnet(
      subnetName,
      VpcId=Ref(vpc),
      AvailabilityZone=config['region'] + subnet['az'],
      CidrBlock=subnet['cidr'],
      Tags=Tags(
        Name=Join('-', [config['account_moniker'], 'Subnet-Private', privateSubnetNumber]),
      ),
      DependsOn=['vpc'],
    ))

      #############################
      # Private Route Association #
      #############################

    rtbAssociationPrivate = t.add_resource(ec2.SubnetRouteTableAssociation(
      'rtbAssociationPrivate' + str(privateSubnetNumber),
      SubnetId=Ref(subnetPrivate),
      RouteTableId=Ref(rtbPrivate),
      DependsOn=[subnetName, 'rtbPrivate'],
    ))

  #######
  # VPN #
  #######

if config['vpn_address'] != None:

      ####################
      # Customer Gateway #
      ####################

    customerGateway = t.add_resource(ec2.CustomerGateway(
      'customerGateway',
      BgpAsn='65000',
      IpAddress=config['vpn_address'],
      Type='ipsec.1',
      Tags=Tags(
        VPN=Join('', ['Gateway to ', config['vpn_address']]),
        Name=Join('-', [config['account_moniker'], 'cgw']),
      ),
    ))

      #########################
      # VPN Route Propagation #
      #########################

    vpnGatewayRoutePropagation = t.add_resource(ec2.VPNGatewayRoutePropagation(
      'vpnGatewayRoutePropagation',
      RouteTableIds=[Ref(rtbPrivate), Ref(rtbPublic)],
      VpnGatewayId=Ref(vpg),
      DependsOn=['rtbPrivate', 'rtbPublic', 'vpg'],
    ))

      ##################
      # VPN Connection #
      ##################

    vpnConnection = t.add_resource(ec2.VPNConnection(
      'vpnConnection',
      Type='ipsec.1',
      StaticRoutesOnly='true',
      CustomerGatewayId=Ref(customerGateway),
      VpnGatewayId=Ref(vpg),
      Tags=Tags(
        Name=Join('-', [config['account_moniker'], 'vpn']),
      ),
      DependsOn=['customerGateway', 'vpg'],
    ))

      ########################
      # VPN Connection Route #
      ########################

    vpnConnectionRoute = t.add_resource(ec2.VPNConnectionRoute(
      'vpnConnectionRoute',
      VpnConnectionId=Ref(vpnConnection),
      DestinationCidrBlock=config['on_premise_cidr'],
      DependsOn=['vpnConnection'],
    ))

with open('./cloudformation/{0}-vpc.json'.format(config['account_moniker']), 'w') as tmpl:
    tmpl.write(t.to_json())
