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
resource "aws_security_group" "lb" {
  name        = "TF-web-sg"
  description = "Allow inbound web traffic to ALB"
  vpc_id      = aws_vpc.main.id

  ingress {
    description      = "HTTP Port from web"
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
  }

  egress {
    description      = "Outbound allow"
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
  }

  #tags = {
  #  Name = "allow_tls"
  #}
}

resource "aws_security_group" "ec2" {
  name        = "TF-ec2-sg"
  description = "Allow traffic from loadbalancer to ec2"
  vpc_id      = aws_vpc.main.id

  ingress {
    description      = "HTTP Port from waf2"
    security_groups  = [aws_security_group.lb.id]
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
  }

  #ingress {
  #  description      = "HTTP Port from waf1"
  #  security_groups  = [aws_security_group.lb.id]
  #  from_port        = 80
  #  to_port          = 80
  #  protocol         = "tcp"
  #}

  ingress {
    description      = "Inbound from Home"
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    cidr_blocks      = ["208.95.71.55/32"]
  }

  egress {
    description      = "Outbound allow"
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
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
  vpc_security_group_ids      = [aws_security_group.ec2.id]
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

###############################################################################
### ALB for WAF1
###############################################################################
resource "aws_lb" "waf1" {

  name               = "TF-waf1-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.lb.id]
  subnets            = [aws_subnet.publicA.id, aws_subnet.publicB.id]

  enable_deletion_protection = false

  #access_logs {
  #  bucket  = aws_s3_bucket.lb_logs.bucket
  #  prefix  = "test-lb"
  #  enabled = true
  #}

  #tags = {
  #  Environment = "production"
  #}
}

resource "aws_lb_listener" "waf1" {
  load_balancer_arn = aws_lb.waf1.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.waf1.arn
  }
}

resource "aws_lb_target_group" "waf1" {
  name     = "TF-waf1-lb-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id
}

resource "aws_lb_target_group_attachment" "waf1" {
  target_group_arn = aws_lb_target_group.waf1.arn
  target_id        = aws_instance.web.id
  port             = 80
}
###############################################################################

###############################################################################
### ALB for WAF2
###############################################################################
resource "aws_lb" "web" {
  name               = "TF-web-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.lb.id]
  subnets            = [aws_subnet.publicA.id, aws_subnet.publicB.id]

  enable_deletion_protection = false

  #access_logs {
  #  bucket  = aws_s3_bucket.lb_logs.bucket
  #  prefix  = "test-lb"
  #  enabled = true
  #}

  #tags = {
  #  Environment = "production"
  #}
}

resource "aws_lb_listener" "front_end" {
  load_balancer_arn = aws_lb.web.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web.arn
  }
}

resource "aws_lb_target_group" "web" {
  name     = "TF-web-lb-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id
}

resource "aws_lb_target_group_attachment" "web" {
  target_group_arn = aws_lb_target_group.web.arn
  target_id        = aws_instance.web.id
  port             = 80
}
###############################################################################

###############################################################################
### Creating the IP Set
###############################################################################
resource "aws_wafv2_ip_set" "ipset" {
  name               = "MyFirstipset"
  description        = "Example IP set created from Terraform"
  scope              = "REGIONAL"
  ip_address_version = "IPV4"
  addresses          = ["208.95.71.55/32"]
}


output "instances" {
  value       = "${aws_instance.web.public_ip}"
  description = "PublicIP address details"
}

output "loadbalancer" {
  value       = "${aws_lb.web.dns_name}"
  description = "Public DNS Endpoint for ALB"
}

output "lb_tg_group_attachment" {
  value       = "${aws_lb_target_group_attachment.web.*}"
  description = "Public DNS Endpoint for ALB"
}