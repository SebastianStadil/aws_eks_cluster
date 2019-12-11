
terraform {
  backend "remote" {
    hostname = "my.scalr.com"
    organization = "xxxxxxxxxx"
    workspaces {
      name = "aws_eks_wordpress"
    }
  }
}

provider "aws" {
    access_key = "${var.scalr_aws_access_key}"
    secret_key = "${var.scalr_aws_secret_key}"
    region     = var.region
}

/*
Create the IAM policy and roles for the cluster
*/

resource "aws_iam_role" "iam_role_cluster" {
  name = "${var.cluster_name}-iam-role"

  assume_role_policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "eks.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
POLICY
}

resource "aws_iam_role_policy_attachment" "demo-cluster-AmazonEKSClusterPolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = "${aws_iam_role.iam_role_cluster.name}"
}

resource "aws_iam_role_policy_attachment" "demo-cluster-AmazonEKSServicePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSServicePolicy"
  role       = "${aws_iam_role.iam_role_cluster.name}"
}

/*
Security rules to allow access to the cluster
*/

resource "aws_security_group" "sg_cluster" {
  name        = "terraform-eks-demo-cluster"
  description = "Cluster communication with worker nodes"
  vpc_id      = "${aws_vpc.eks_vpc.id}"

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.cluster_name}-sg"
  }
}

/*
# OPTIONAL: Allow inbound traffic from your local workstation external IP
#           to the Kubernetes. You will need to replace A.B.C.D below with
#           your real IP. Services like icanhazip.com can help you find this.
resource "aws_security_group_rule" "demo-cluster-ingress-workstation-https" {
  cidr_blocks       = ["A.B.C.D/32"]
  description       = "Allow workstation to communicate with the cluster API Server"
  from_port         = 443
  protocol          = "tcp"
  security_group_id = "${aws_security_group.demo-cluster.id}"
  to_port           = 443
  type              = "ingress"
}
*/

/*
The master cluster
*/

resource "aws_eks_cluster" "cluster_1" {
  name            = "${var.cluster_name}"
  role_arn        = "${aws_iam_role.iam_role_cluster.arn}"

  vpc_config {
    security_group_ids = ["${aws_security_group.sg_cluster.id}"]
    subnet_ids         = "${aws_subnet.eks_subnet.*.id}"
  }

  depends_on = [
    "aws_iam_role_policy_attachment.demo-cluster-AmazonEKSClusterPolicy",
    "aws_iam_role_policy_attachment.demo-cluster-AmazonEKSServicePolicy",
  ]
}


# kubectl config


locals {
  kubeconfig = <<KUBECONFIG

apiVersion: v1
clusters:
- cluster:
    server: ${aws_eks_cluster.cluster_1.endpoint}
    certificate-authority-data: ${aws_eks_cluster.cluster_1.certificate_authority.0.data}
  name: kubernetes
contexts:
- context:
    cluster: kubernetes
    user: aws
  name: aws
current-context: aws
kind: Config
preferences: {}
users:
- name: aws
  user:
    exec:
      apiVersion: client.authentication.k8s.io/v1alpha1
      command: aws-iam-authenticator
      args:
        - "token"
        - "-i"
        - "${var.cluster_name}"
KUBECONFIG
}

resource "local_file" "kube_config" {
  content    = local.kubeconfig
  filename   = "kubeconfig/${var.cluster_name}-cfg"
}


# Add Nodes


resource "aws_iam_role" "iam_role_worker" {
  name = "${var.cluster_name}-iam-role-worker"

  assume_role_policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
POLICY
}

resource "aws_iam_role_policy_attachment" "tf-eks-node-AmazonEKSWorkerNodePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = "${aws_iam_role.iam_role_worker.name}"
}

resource "aws_iam_role_policy_attachment" "tf-eks-node-AmazonEKS_CNI_Policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = "${aws_iam_role.iam_role_worker.name}"
}

resource "aws_iam_role_policy_attachment" "tf-eks-node-AmazonEC2ContainerRegistryReadOnly" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = "${aws_iam_role.iam_role_worker.name}"
}

resource "aws_iam_instance_profile" "iamp_worker" {
  name = "${var.cluster_name}-eks-node-iamp"
  role = "${aws_iam_role.iam_role_worker.name}"
}

# Worker Node Security Group

resource "aws_security_group" "sg_worker" {
  name        = "${var.cluster_name}-sg-worker"
  description = "Security group for all nodes in the cluster"
  vpc_id      = aws_vpc.eks_vpc.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    "Name"                                      = "${var.cluster_name}-sg-worker"
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
  }
}

resource "aws_security_group_rule" "eks-demo_ingress_self" {
  description              = "Allow node to communicate with each other"
  from_port                = 0
  protocol                 = "-1"
  security_group_id        = aws_security_group.sg_worker.id
  source_security_group_id = aws_security_group.sg_worker.id
  to_port                  = 65535
  type                     = "ingress"
}

resource "aws_security_group_rule" "eks_demo_ingress_cluster" {
  description              = "Allow worker Kubelets and pods to receive communication from the cluster control      plane"
  from_port                = 1025
  protocol                 = "tcp"
  security_group_id        = aws_security_group.sg_worker.id
  source_security_group_id = aws_security_group.sg_worker.id
  to_port                  = 65535
  type                     = "ingress"
 }

 resource "aws_security_group_rule" "eks_demo_cluster_ingress_node_https" {
  description              = "Allow pods to communicate with the cluster API Server"
  from_port                = 443
  protocol                 = "tcp"
  security_group_id        = aws_security_group.sg_cluster.id
  source_security_group_id = aws_security_group.sg_worker.id
  to_port                  = 443
  type                     = "ingress"
}

# »Worker Node Group

locals {
  min_nodes = var.minimum_nodes <= local.azs ? var.minimum_nodes : local.azs
}

resource "aws_eks_node_group" "eks_node_group" {
  cluster_name    = aws_eks_cluster.cluster_1.name
  node_group_name = "eks_node_group"
  node_role_arn   = aws_iam_role.iam_role_worker.arn
  subnet_ids      = aws_subnet.eks_subnet[*].id
  instance_types  = [var.instance_type]

  scaling_config {
    desired_size = var.number_of_azs <= length(data.aws_availability_zones.available.names) ? var.number_of_azs : length(data.aws_availability_zones.available.names)
    max_size     = var.number_of_azs <= length(data.aws_availability_zones.available.names) ? var.number_of_azs : length(data.aws_availability_zones.available.names)
    min_size     = local.min_nodes
  }

  remote_access {
    ec2_ssh_key = var.key_name
  }
}

output "eks_kubeconfig" {
  value = "${local.kubeconfig}"
  depends_on = [
    "aws_eks_cluster.cluster_1"
  ]
}
