variable "generation" {
  type    = number
  default = 2
}

variable "ibmcloud_api_key" {
  type = string
}

variable "region" {
  type    = string
  default = "eu-gb"
}

variable "resource_group" {
  type    = string
  default = "Default"
}

variable "cluster_name" {
  type = string
}

variable "tags" {
  type    = list(string)
  default = []
}

# from ibmcloud ks flavors --zone $ZONE --provider vpc-gen2
variable "worker_flavor" {
  type    = string
  default = "bx2.4x16"
}

variable "entitlement" {
  type    = string
  default = "cloud_pak"
}

variable "workers_per_zone" {
  type    = number
  default = 1
}

# from ibmcloud ks flavors --zone $ZONE --provider vpc-gen2
variable "ocs_flavor" {
  type    = string
  default = "bx2.16x64"
}

variable "create_resource_group" {
  type    = bool
  default = false
}