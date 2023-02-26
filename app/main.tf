variable "input" {
  type = string
}

output "result" {
  value = "app returns:  ${var.input}"
}
