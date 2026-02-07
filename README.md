# Terraform AWS ALB + ASG Demo 🚀

## Overview
This project deploys a **highly available web application** on AWS using Terraform:  

- **VPC** with public/private subnets  
- **Application Load Balancer (ALB)**  
- **Auto Scaling Group (ASG)** with EC2 instances  
- **Nginx** serving a simple web page  

---

## Architecture

Internet
|
v
[ALB] --> [EC2 Instances in Private Subnets]
|
[Nginx Serving Content]

