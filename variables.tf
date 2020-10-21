
variable "ibmcloud_api_key" {
  type = string
}

variable "resource_group" {
  type    = string
}

variable "create_resource_group" {
  type    = bool
}

variable "cluster_name" {
  type = string
}

variable "tags" {
  type    = list(string)
  default = []
}

variable "region" {
  type    = string
  default = "eu-gb"
}

# from ibmcloud ks flavors --zone $ZONE --provider vpc-gen2
variable "worker_flavor" {
  type    = string
  default = "bx2.4x16"
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

variable "entitlement" {
  type    = string
  default = "cloud_pak"
}

#this is set for future reqs if needed

variable "generation" {
  type    = number
  default = 2
}