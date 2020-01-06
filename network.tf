# This data source is included for ease of sample architecture deployment
 # and can be swapped out as necessary.
 data "aws_availability_zones" "available" {
 }

# This is designed to ensure we dont try to add more subnets than there are AZ's
# But due to Terraform bug #21662 the use of a local in the count param causes cycle errors during destroy
# So this is only here for future use.

 locals {
   azs = var.number_of_azs <= length(data.aws_availability_zones.available.names) ? var.number_of_azs : length(data.aws_availability_zones.available.names)
 }

 resource "aws_vpc" "eks_vpc" {
   cidr_block = "10.0.0.0/16"

   tags = {
     "Name"                                      = "${var.cluster_name}-vpc-${random_string.random.result}"
     "kubernetes.io/cluster/${var.cluster_name}" = "shared"
   }
 }

 resource "aws_subnet" "eks_subnet" {
#   count = local.azs
   count = var.number_of_azs <= length(data.aws_availability_zones.available.names) ? var.number_of_azs : length(data.aws_availability_zones.available.names)

   availability_zone = data.aws_availability_zones.available.names[count.index]
   cidr_block        = "10.0.${count.index}.0/24"
   vpc_id            = aws_vpc.eks_vpc.id

   tags = {
     "Name"                                      = "${var.cluster_name}-subnet-${random_string.random.result}"
     "kubernetes.io/cluster/${var.cluster_name}" = "shared"
   }
 }

 resource "aws_internet_gateway" "igw_cluster" {
   vpc_id = aws_vpc.eks_vpc.id

   tags = {
     Name = "${var.cluster_name}-igw-${random_string.random.result}"
   }
 }

 resource "aws_route_table" "route_table" {
   vpc_id = aws_vpc.eks_vpc.id

   route {
     cidr_block = "0.0.0.0/0"
     gateway_id = aws_internet_gateway.igw_cluster.id
   }
 }

 resource "aws_route_table_association" "rt_assoc" {
#   count = local.azs
   count = var.number_of_azs <= length(data.aws_availability_zones.available.names) ? var.number_of_azs : length(data.aws_availability_zones.available.names)

   subnet_id      = aws_subnet.eks_subnet[count.index].id
   route_table_id = aws_route_table.route_table.id
 }
