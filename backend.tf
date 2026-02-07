terraform {
  backend "s3" {
    bucket         = "amzn-s3-state-bucket"
    key            = "terraform.tfstate"
    region         = "eu-north-1"
    dynamodb_table = "state-lock"
   
  }
}