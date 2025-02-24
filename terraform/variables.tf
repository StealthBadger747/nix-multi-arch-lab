variable "tenancy_ocid" {
  description = "The OCID of your tenancy"
  sensitive   = true
}

variable "compartment_ocid" {
  description = "The OCID of the compartment where resources will be created"
  sensitive   = true
}

variable "region" {
  description = "The OCI region where resources will be created"
  type        = string
}

variable "instance_name" {
  description = "Name of the instance"
}

variable "ssh_public_key" {
  description = "The path to the SSH public key file used for SSH access to the instances"
  sensitive   = true
}

variable "ssh_private_key" {
  description = "The path to the SSH private key file used for SSH access to the instances when generating ansible inventory.ini file"
  sensitive   = true
}

variable "namespace" {
  description = "OCI Object Storage namespace"
  type        = string
}
