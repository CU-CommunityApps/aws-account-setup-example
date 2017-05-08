#!/bin/bash

while true; do
  read -p "Have you set your account configuration in onboard.yml? [y/n] " yn
  case $yn in
    [Yy]* ) break;;
    [Nn]* ) exit;;
    * )     echo "Answer y/n";;
  esac
done

while true; do
  read -p "Do you want to set up SAML / Shibboleth for this account? [y/n] " yn
  case $yn in
    [Yy]* ) ./scripts/shib.rb; break;;
    [Nn]* ) break;;
    * )     echo "Answer y/n";;
  esac
done

while true; do
  read -p "Do you want to set up ConfigService for this account? [y/n] " yn
  case $yn in
    [Yy]* ) ./scripts/config.rb; break;;
    [Nn]* ) break;;
    * )     echo "Answer y/n";;
  esac
done

while true; do
  read -p "Do you want to generate CloudFormation templates for Auditing / VPC configuration? [y/n] " yn
  case $yn in
    [Yy]* ) ./scripts/cloudformation.py; ./scripts/apply-cloudformation.rb; break;;
    [Nn]* ) break;;
    * )     echo "Answer y/n";;
  esac
done

while true; do
  read -p "Do you want to set up VPC Flow Logs for this account? [y/n] " yn
  case $yn in
    [Yy]* ) ./scripts/flow.rb; break;;
    [Nn]* ) break;;
    * )     echo "Answer y/n";;
  esac
done

while true; do
  read -p "Do you want to NUKE default NACL's and reset to default CU rules? [y/n] " yn
  case $yn in
    [Yy]* ) ./scripts/nacls.rb; break;;
    [Nn]* ) break;;
    * )     echo "Answer y/n";;
  esac
done

