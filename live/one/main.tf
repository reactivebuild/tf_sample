terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.55.0"
    }
  }
}

variable "input_to_one" {
  type = string
  default = "Input To One"
}

output "output_from_one" {
  value = "Output from two is ${var.input_to_one} version 2"
}
