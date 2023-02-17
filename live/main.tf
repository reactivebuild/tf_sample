module "app" {
  source = "../app"
}

output "Status" {
  value = module.app.result
}