provider "aws" {
  region = var.region
}

locals {
  aws_suffix = random_string.rand_aws_suffix.result
  ecs_name = "consul-ecs-${random_string.rand_aws_suffix.result}"
  launch_type = "FARGATE"
}

data "aws_availability_zones" "available" {
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

resource "random_string" "rand_aws_suffix" {
  length  = 6
  special = false
}

resource "random_shuffle" "azs" {
  input = data.aws_availability_zones.available.names
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "2.78.0"

  name = local.ecs_name
  cidr = "10.0.0.0/16"
  // The NAT gateway limit is per AZ. With `single_nat_gateway = true`, the NAT gateway is created
  // in the first public subnet. Shuffling AZs helps spread NAT gateways across AZs to help with this.
  azs = [
    // Silly, but avoids this error: `"count" value depends on resource attributes that cannot be determined until apply`
    random_shuffle.azs.result[0],
    random_shuffle.azs.result[1],
    random_shuffle.azs.result[2],
  ]
  private_subnets      = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets       = ["10.0.4.0/24", "10.0.5.0/24", "10.0.6.0/24"]
  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true
  tags                 = var.tags
}

resource "aws_ecs_cluster" "cluster_1" {
  name               = "${local.ecs_name}-1"
  tags               = var.tags
}

resource "aws_ecs_cluster_capacity_providers" "ecs_ccp_1" {
  cluster_name = aws_ecs_cluster.cluster_1.name
  capacity_providers = [local.launch_type]

  default_capacity_provider_strategy {
    capacity_provider = local.launch_type
  }
}

resource "aws_ecs_cluster" "cluster_2" {
  name               = "${local.ecs_name}-2"
  tags               = var.tags
}

resource "aws_ecs_cluster_capacity_providers" "ecs_ccp_2" {
  cluster_name = aws_ecs_cluster.cluster_2.name
  capacity_providers = [local.launch_type]

  default_capacity_provider_strategy {
    capacity_provider = local.launch_type
  }
}

resource "aws_cloudwatch_log_group" "log_group" {
  name = local.ecs_name
  tags = var.tags
}

// Policy that allows execution of remote commands in ECS tasks.
resource "aws_iam_policy" "execute_command" {
  name   = "ecs-execute-command-${local.aws_suffix}"
  path   = "/"
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ssmmessages:CreateControlChannel",
        "ssmmessages:CreateDataChannel",
        "ssmmessages:OpenControlChannel",
        "ssmmessages:OpenDataChannel"
      ],
      "Resource": [
        "*"
      ]
    }
  ]
}
EOF

}
