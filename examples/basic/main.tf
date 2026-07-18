terraform {
  required_version = ">= 1.5"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 3.0"
    }
  }
}

provider "azurerm" {
  features {}
}

module "application_gateway" {
  source = "../.."

  name                = "example-appgw"
  resource_group_name = "example-rg"
  location            = "eastus"

  subnet_id            = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/example-rg/providers/Microsoft.Network/virtualNetworks/example-vnet/subnets/appgw-subnet"
  public_ip_address_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/example-rg/providers/Microsoft.Network/publicIPAddresses/example-appgw-pip"

  tags = {
    Environment = "sandbox"
    ManagedBy   = "terraform"
  }
}

output "application_gateway_id" {
  value = module.application_gateway.id
}
