#User vars
variable "azure_region" { default = "eastus" }
variable "env" { default = "rg-usecase5" }

variable "ports" {
  type    = list(string)
  default = ["22", "80"]
}

