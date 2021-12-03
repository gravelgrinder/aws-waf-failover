terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.27"
    }
  }

  required_version = ">= 0.14.9"
}

provider "aws" {
  profile = "default"
  region  = "us-east-1"
}




###############################################################################
### Create VPC, Internet Gateway & Subnets
###############################################################################
resource "aws_vpc" "main" {
  cidr_block       = "10.0.0.0/16"
  instance_tenancy = "default"

  tags = {
    Name = "TF-main"
  }
}
###############################################################################


###############################################################################
### Create Internet Gateway
###############################################################################
resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "TF-main"
  }
}
###############################################################################


###############################################################################
### Create Subnets (Public/Private)
###############################################################################
resource "aws_subnet" "publicA" {
  vpc_id     = aws_vpc.main.id
  cidr_block = "10.0.0.0/24"

  tags = {
    Name = "TF-main-public-A"
  }
}

resource "aws_subnet" "publicB" {
  vpc_id     = aws_vpc.main.id
  cidr_block = "10.0.1.0/24"

  tags = {
    Name = "TF-main-public-B"
  }
}
###############################################################################


###############################################################################
### Create Route Table & associations
###############################################################################
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  tags = {
    Name = "TF-main-public-rt"
  }
}

resource "aws_route_table_association" "a" {
  subnet_id      = aws_subnet.publicA.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "b" {
  subnet_id      = aws_subnet.publicB.id
  route_table_id = aws_route_table.public.id
}
###############################################################################

###############################################################################
### Web Security Group
###############################################################################
resource "aws_security_group" "web" {
  name        = "TF-web-sg"
  description = "Allow inbound web traffic"
  vpc_id      = aws_vpc.main.id

  ingress {
    description      = "TLS from VPC"
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    cidr_blocks      = [aws_vpc.main.cidr_block]
    ipv6_cidr_blocks = [aws_vpc.main.ipv6_cidr_block]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name = "allow_tls"
  }
}
###############################################################################


###############################################################################
### EC2 Web Server
###############################################################################
resource "aws_instance" "web" {
  ami                         = "ami-0ed9277fb7eb570c9" 
  instance_type               = "t2.micro"
  subnet_id                   = aws_subnet.publicA.id
  #availability_zone           = "us-east-1"
  associate_public_ip_address = "true"
  key_name                    = "DemoVPC_Key_Pair"
  vpc_security_group_ids      = ["sg-02c55e1e2370fa1df"]
  user_data = <<EOF
#!/bin/bash

########################################
##### USE THIS WITH AMAZON LINUX 2 #####
########################################

# get admin privileges
sudo su

# install httpd (Linux 2 version)
yum update -y
yum install -y httpd.x86_64
systemctl start httpd.service
systemctl enable httpd.service
echo "Hello World from $(hostname -f)" > /var/www/html/index.html

EOF

  tags = {
    Name = "TF-main-web-instance"
  }
}
###############################################################################

output "instances" {
  value       = "${aws_instance.web.*.private_ip}"
  description = "PrivateIP address details"
}