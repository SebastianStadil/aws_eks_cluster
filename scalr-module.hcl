version = "v1"

variable "region" {
  policy = "cloud.locations"
  conditions = {
  cloud = "ec2"
  }
}

variable "instance_type" {
  policy = "cloud.instance.types"
  conditions = {
    cloud = "ec2"
  }
}

variable "cluster_name" {
  global_variable = "name_fmt"
}

variable "number_of_azs" {
  global_variable = "numeric_fmt"
}

variable "minimum_nodes" {
  global_variable = "numeric_fmt"
}
