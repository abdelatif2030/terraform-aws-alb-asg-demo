# -------------------------------
# Variables for Names
# -------------------------------
variable "alb_name" {
  type    = string
  default = "app-alb-demo"
}

variable "tg_name" {
  type    = string
  default = "app-tg-demo"
}

variable "key_name" {
  type    = string
  default = "terraform"   # اسم الـ key pair عندك
}

# -------------------------------
# Data: Availability Zones
# -------------------------------
data "aws_availability_zones" "available" {}

# -------------------------------
# VPC
# -------------------------------
resource "aws_vpc" "this" {
  cidr_block = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = { Name = "demo-vpc" }
}

# -------------------------------
# Internet Gateway
# -------------------------------
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "demo-igw" }
}

# -------------------------------
# Public Route Table
# -------------------------------
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = { Name = "public-rt" }
}

# -------------------------------
# Public Subnets (2 AZs)
# -------------------------------
resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.this.id
  cidr_block              = cidrsubnet("10.0.0.0/16", 8, count.index)
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true
  tags = { Name = "public-subnet-${count.index + 1}" }
}

# Associate Public Subnets with Route Table
resource "aws_route_table_association" "public_assoc" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public_rt.id
}

# -------------------------------
# Private Subnets (2 AZs)
# -------------------------------
resource "aws_subnet" "private" {
  count                   = 2
  vpc_id                  = aws_vpc.this.id
  cidr_block              = cidrsubnet("10.0.0.0/16", 8, count.index + 10)
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = false
  tags = { Name = "private-subnet-${count.index + 1}" }
}

# -------------------------------
# Security Groups
# -------------------------------
# ALB SG
resource "aws_security_group" "alb_sg" {
  name   = "alb-sg"
  vpc_id = aws_vpc.this.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]   # يسمح لأي IP
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# EC2 SG
resource "aws_security_group" "ec2_sg" {
  name   = "ec2-sg"
  vpc_id = aws_vpc.this.id

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]   # SSH لأي IP (لتجربة فقط)
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# -------------------------------
# Launch Template
# -------------------------------
resource "aws_launch_template" "app_lt" {
  name          = "app-lt"
  image_id      = "ami-073130f74f5ffb161"  # Ubuntu
  instance_type = "t3.micro"
  key_name      = var.key_name

  network_interfaces {
    associate_public_ip_address = false
    security_groups             = [aws_security_group.ec2_sg.id]
  }

  # تثبيت Apache تلقائي على port 80
  user_data = base64encode(<<EOF
#!/bin/bash
apt update -y
apt install -y apache2
systemctl enable apache2
systemctl start apache2
echo "Hello from Terraform ALB Demo!" > /var/www/html/index.html
EOF
)

  metadata_options {
    http_tokens = "required"
  }

  tag_specifications {
    resource_type = "instance"
    tags = { Name = "asg-instance" }
  }
}

# -------------------------------
# Auto Scaling Group (Private)
# -------------------------------
resource "aws_autoscaling_group" "app_asg" {
  desired_capacity     = 2
  max_size             = 3
  min_size             = 1
  vpc_zone_identifier  = aws_subnet.private[*].id

  launch_template {
    id      = aws_launch_template.app_lt.id
    version = "$Latest"
  }

  health_check_type         = "ELB"
  health_check_grace_period = 30
}

# -------------------------------
# ALB (Public)
# -------------------------------
resource "aws_lb" "app_alb" {
  name               = var.alb_name
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = aws_subnet.public[*].id
}

# -------------------------------
# Target Group
# -------------------------------
resource "aws_lb_target_group" "app_tg" {
  name     = var.tg_name
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.this.id

  health_check {
    path                = "/"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 3
    unhealthy_threshold = 2
    matcher             = "200"
  }
}

# -------------------------------
# Listener
# -------------------------------
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.app_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app_tg.arn
  }
}

# -------------------------------
# Attach ASG to Target Group
# -------------------------------
resource "aws_autoscaling_attachment" "asg_attachment" {
  autoscaling_group_name = aws_autoscaling_group.app_asg.name
  lb_target_group_arn    = aws_lb_target_group.app_tg.arn
}

# -------------------------------
# Outputs
# -------------------------------
output "alb_dns_name" {
  value = aws_lb.app_alb.dns_name
}

output "asg_name" {
  value = aws_autoscaling_group.app_asg.name
}
