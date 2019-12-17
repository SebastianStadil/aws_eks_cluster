variable "scalr_aws_secret_key" {}
variable "scalr_aws_access_key" {}

variable "cluster_name" {
  type    = string
}

variable "region" {
  description = "The AWS Region to deploy in"
  type        = string
}


variable "instance_type" {
  description = "Instance type for the cluster nodes"
  default     = "t3.medium"
  type        = string
}


variable "key_name" {
  description = "The name of then public SSH key to be deployed to the servers. This must exist in AWS already"
  type        = string
}


variable number_of_azs {
  description = "Number of availability_zones to deploy to, and therefore minimum number of desired worker nodes"
  default     = 2
  type        = string
}

variable minimum_nodes {
  description = "Minimum number of worker nodes, must be <= number_of_azs"
  default     = 1
  type        = string
}
