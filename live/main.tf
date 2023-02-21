module "app" {
  source = "../app"

  input = var.in
}

variable "in" {
  type = string
  default = "input value"
}

output "Status" {
  value = module.app.result
}