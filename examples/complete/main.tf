terraform {
  required_version = ">= 1.5"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 3.66.0, < 6.0"
    }
  }
}

provider "azurerm" {
  features {}
}

# A WAF_v2 gateway that terminates TLS 1.2+ with a certificate from Key Vault,
# permanently redirects plain HTTP to HTTPS, and talks HTTPS to its backends.
module "application_gateway" {
  source = "../.."

  name                = "example-appgw"
  resource_group_name = "example-rg"
  location            = "eastus"

  subnet_id            = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/example-rg/providers/Microsoft.Network/virtualNetworks/example-vnet/subnets/appgw-subnet"
  public_ip_address_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/example-rg/providers/Microsoft.Network/publicIPAddresses/example-appgw-pip"

  sku_name = "WAF_v2"
  sku_tier = "WAF_v2"

  waf_firewall_mode    = "Prevention"
  waf_rule_set_version = "3.2"

  identity_ids = [
    "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/example-rg/providers/Microsoft.ManagedIdentity/userAssignedIdentities/example-appgw",
  ]
  ssl_certificate_key_vault_secret_id = "https://example-kv.vault.azure.net/secrets/example-appgw-cert"
  https_host_name                     = "www.example.com"

  ssl_policy_type = "Predefined"
  ssl_policy_name = "AppGwSslPolicy20220101S"

  # End-to-end TLS: the gateway re-encrypts on the way to the backend pool.
  backend_protocol = "Https"
  backend_port     = 443

  # Send each backend's own host name and probe a health path instead of
  # Azure's default GET / with the client's Host header.
  backend_pick_host_name_from_backend_address = true

  probe = {
    path = "/healthz"
  }

  tags = {
    Environment = "sandbox"
    ManagedBy   = "terraform"
  }
}

output "application_gateway_id" {
  value = module.application_gateway.id
}
