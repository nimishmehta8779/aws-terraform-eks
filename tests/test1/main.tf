provider "aws" {
  version = "~> 2.7"
  region  = "us-west-2"
}

provider "template" {
  version = "~> 1.0"
}

provider "random" {
  version = "~> 1.0"
}

resource "random_string" "name_rstring" {
  length  = 8
  special = false
}

locals {
  eks_cluster_name = "Test-EKS"
}

module "vpc" {
  source = "git@github.com:rackspace-infrastructure-automation/aws-terraform-vpc_basenetwork//?ref=master"

  vpc_name = "Test1VPC"

  custom_tags = "${map("kubernetes.io/cluster/${local.eks_cluster_name}", "shared")}"
}

module "sg" {
  source = "git@github.com:rackspace-infrastructure-automation/aws-terraform-security_group//?ref=master"

  resource_name = "Test-SG"
  vpc_id        = "${module.vpc.vpc_id}"
}

module "eks" {
  source = "../../module"

  name                      = "${random_string.name_rstring.result}-${local.eks_cluster_name}"
  enabled_cluster_log_types = []                                                                 #  All are enabled by default. Test to ensure disabling doesn't break
  subnets                   = "${concat(module.vpc.private_subnets, module.vpc.public_subnets)}" #  Required
  security_groups           = ["${module.sg.eks_control_plane_security_group_id}"]
  worker_roles              = ["${module.ec2_asg.iam_role}"]
  worker_roles_count        = "1"

  # kubernetes_version = ""
}

# Lookup the correct AMI based on the region specified
data "aws_ami" "eks" {
  most_recent = true
  owners      = ["602401143452"]

  filter {
    name   = "name"
    values = ["amazon-eks-node-*"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

module "ec2_asg" {
  source = "git@github.com:rackspace-infrastructure-automation/aws-terraform-ec2_asg//?ref=master"

  ec2_os                    = "amazoneks"
  subnets                   = ["${module.vpc.private_subnets}"]
  image_id                  = "${data.aws_ami.eks.image_id}"
  instance_type             = "t2.medium"
  resource_name             = "my_eks_worker_nodes"
  security_group_list       = ["${module.sg.eks_worker_security_group_id}"]
  initial_userdata_commands = "${module.eks.setup}"

  additional_tags = [
    {
      key                 = "kubernetes.io/cluster/${module.eks.name}"
      value               = "owned"
      propagate_at_launch = true
    },
  ]
}
