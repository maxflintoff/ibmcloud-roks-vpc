# ROKS & OCS for IBM Cloud

This repository houses a set of automation for deploying infrastructure, a ROKS 4.4 Openshift cluster and Openshift Container Storage

## Prerequisites

- terraform > 0.13.4

## Variables

There are a few variables that must be set for the install to take place successfully.

- [ibmcloud_api_key](https://cloud.ibm.com/docs/iam?topic=iam-userapikey)
- resource_group
- cluster_name
  
Additionally it is recommended to set additional variables:

- tags (a list of strings of tags to apply to the infrastructure)

## Deployment

To run this deployment run this series of commands from the root folder

```bash
# Optional commands
terraform init
terraform plan #check your plan is as expected
terraform apply
```