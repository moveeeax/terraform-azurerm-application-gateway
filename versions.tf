terraform {
  required_version = ">= 1.5"

  required_providers {
    # Floor: CustomV2 SSL policies only work from 3.66.0 (the provider did not
    # send min_protocol_version before). Ceiling: tested on 5.x, not on 6.x.
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 3.66.0, < 6.0"
    }
  }
}
