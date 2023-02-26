module "one" {
  source = "../one"
}

module "app" {
  source = "../../app"

  input = module.one.output_from_one
}

output "output_from_two" {
  value = module.app.result
}
