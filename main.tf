provider "aws" {
  version = "~> 2.0"
  region  = "us-east-1"
}

resource "aws_subnet" "example" {
  for_each = var.subnet_numbers

  vpc_id            = aws_vpc.default.id
  availability_zone = each.value
  cidr_block        = each.key
}

resource "aws_subnet" "public-a" {
  vpc_id     = aws_vpc.default.id
  cidr_block = "10.0.6.0/24"
  availability_zone = "us-east-1a"
 

  tags = {
    Name = "public-a-tf"
  }
}

 

resource "aws_subnet" "public-b" {
  vpc_id     = aws_vpc.default.id
  cidr_block = "10.0.7.0/24"
  availability_zone = "us-east-1b"
 

  tags = {
    Name = "public-b-tf"
  }
}

resource "aws_vpc" "default" {
  cidr_block = "10.0.0.0/16"
  
  tags = {
    Name = "terraform"
  }
}


resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.default.id

  tags = {
    Name = "igw-tf"
  }
}

resource "aws_route_table" "r" {
  vpc_id = aws_vpc.default.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }
  tags = {
    Name = "internet-tf"
  }
}

resource "aws_route_table_association" "a" {
  subnet_id      = aws_subnet.example["10.0.1.0/24"].id
  route_table_id = aws_route_table.r.id
}

resource "aws_route_table_association" "b" {
  subnet_id      = aws_subnet.example["10.0.2.0/24"].id
  route_table_id = aws_route_table.r.id
}

resource "tls_private_key" "example" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "deployer" {
  key_name   = "ec2-key-tf"
  public_key = tls_private_key.example.public_key_openssh
}

data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-bionic-18.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"] # Canonical 
}

resource "aws_security_group" "allow_http" {
  name        = "allow_tls"
  description = "Allow http inbound traffic"
  vpc_id      = "${aws_vpc.default.id}"

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  egress {
  from_port   = 0
  to_port     = 0
  protocol    = "-1"
  cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "allow_http-tf"
  }
}

#Create loadbalancer
resource "aws_lb" "alb_terraform" {
  name               = "alb-terraform"
  internal           = false
  load_balancer_type = "application"
  security_groups    = ["${aws_security_group.allow_http.id}"]
  subnets            = ["${aws_subnet.public-a.id}", "${aws_subnet.public-b.id}"]
}

resource "aws_lb_target_group" "target_group_tf" {
  name     = "target-group-tf"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.default.id
}

resource "aws_lb_listener" "front_end" {
  load_balancer_arn = "${aws_lb.alb_terraform.arn}"
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = "Fixed response content"
      status_code  = "200"
    }
  }
}

resource "aws_launch_configuration" "al_conf" {
  name_prefix   = "terraform-lc"
  image_id      = "${data.aws_ami.ubuntu.id}"
  instance_type = "t2.micro"
  associate_public_ip_address = true
  key_name = aws_key_pair.deployer.key_name
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "bar" {
  name                 = "terraform-asg"
  launch_configuration = "${aws_launch_configuration.al_conf.name}"
  min_size             = 2
  max_size             = 3
  availability_zones = ["${aws_subnet.public-a.availability_zone}", "${aws_subnet.public-b.availability_zone}"]
  
  
  lifecycle {
    create_before_destroy = true
  }
}

data "template_file" "ami_name" {
  template = "${file("${path.module}/postinstall.sh")}"
  vars = {
    ami_name = data.aws_ami.ubuntu.name
  }
}

output "private-key" {
  value = tls_private_key.example.private_key_pem
}

output "ami-value" {
  value = data.aws_ami.ubuntu.image_id
}



