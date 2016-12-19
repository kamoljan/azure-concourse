#!/bin/bash
set -e

echo "=============================================================================================="
echo "Executing Terraform ...."
echo "=============================================================================================="

# Copy base template with no clobber if not using the base template
if [[ ! ${azure_pcf_terraform_template} == "c0-azure-base" ]]; then
  cp -rn azure-concourse/terraform/c0-azure-base/* azure-concourse/terraform/${azure_pcf_terraform_template}/
fi

# Get ert subnet if multi-resgroup
ert_subnet_cmd="azure network vnet subnet list -g network-core  -e vnet-pcf --json | jq '.[] | select(.name == \"ert\") | .id' | tr -d '\"'"
ert_subnet=$(eval $ert_subnet_cmd)
echo "Found SubnetID=${ert_subnet}"


export PATH=/opt/terraform:$PATH

function fn_terraform {

/opt/terraform/terraform ${1} \
  -var "subscription_id=${azure_subscription_id}" \
  -var "client_id=${azure_service_principal_id}" \
  -var "client_secret=${azure_service_principal_password}" \
  -var "tenant_id=${azure_tenant_id}" \
  -var "location=${azure_region}" \
  -var "env_name=${azure_terraform_prefix}" \
  -var "azure_terraform_vnet_cidr=${azure_terraform_vnet_cidr}" \
  -var "azure_terraform_subnet_infra_cidr=${azure_terraform_subnet_infra_cidr}" \
  -var "azure_terraform_subnet_ert_cidr=${azure_terraform_subnet_ert_cidr}" \
  -var "azure_terraform_subnet_services1_cidr=${azure_terraform_subnet_services1_cidr}" \
  -var "azure_terraform_subnet_dynamic_services_cidr=${azure_terraform_subnet_dynamic_services_cidr}" \
  -var "ert_subnet_id=${ert_subnet}" \
  azure-concourse/terraform/${azure_pcf_terraform_template}/init

}

fn_terraform "plan"
fn_terraform "apply"


echo "=============================================================================================="
echo "This azure_pcf_terraform_template has an 'Init' set of terraform that has pre-created IPs..."
echo "=============================================================================================="


azure login --service-principal -u ${azure_service_principal_id} -p ${azure_service_principal_password} --tenant ${azure_tenant_id}



function fn_get_ip {
     azure_cmd="azure network public-ip list -g ${azure_terraform_prefix} --json | jq '.[] | select( .name | contains(\"${1}\")) | .ipAddress' | tr -d '\"'"
     pub_ip=$(eval $azure_cmd)
     echo $pub_ip
}

pub_ip_pcf_lb=$(fn_get_ip "web-lb")
pub_ip_tcp_lb=$(fn_get_ip "tcp-lb")
pub_ip_ssh_proxy_lb=$(fn_get_ip "ssh-proxy-lb")
pub_ip_opsman_vm=$(fn_get_ip "opsman")
pub_ip_jumpbox_vm=$(fn_get_ip "jb")

priv_ip_mysql=$(azure network lb frontend-ip list -g ${azure_terraform_prefix} -l ${azure_terraform_prefix}-mysql-lb --json | jq .[].privateIPAddress | tr -d '"')


echo "You have now deployed Public IPs to azure that must be resolvable to:"
echo "----------------------------------------------------------------------------------------------"
echo "*.sys.${pcf_ert_domain} == ${pub_ip_pcf_lb}"
echo "*.cfapps.${pcf_ert_domain} == ${pub_ip_pcf_lb}"
echo "ssh.sys.${pcf_ert_domain} == ${pub_ip_ssh_proxy_lb}"
echo "tcp.${pcf_ert_domain} == ${pub_ip_tcp_lb}"
echo "opsman.${pcf_ert_domain} == ${pub_ip_opsman_vm}"
echo "jumpbox.${pcf_ert_domain} == ${pub_ip_jumpbox_vm}"
echo "mysql-proxy-lb.sys.${pcf_ert_domain} == ${priv_ip_mysql}"
echo "----------------------------------------------------------------------------------------------"
echo "DO Not Start the 'deploy-iaas' Concourse Job of this Pipeline until you have confirmed that DNS is reolving correctly.  Failure to do so will result in a FAIL!!!!"
