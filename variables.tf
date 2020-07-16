variable "instance_type" {
  type = string
  default = "t2.micro"
}

variable "subnet_numbers" {
  default     = {
    "10.0.1.0/24" = "us-east-1a"
    "10.0.2.0/24" = "us-east-1b"
  }
}