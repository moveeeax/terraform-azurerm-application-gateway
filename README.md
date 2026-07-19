# terraform-azurerm-application-gateway

Terraform module that manages an [Azure](https://azure.microsoft.com/)
Application Gateway. It wires up a complete v2 gateway - gateway IP
configuration, frontend port and public IP, a backend pool, HTTP settings, an
HTTP listener and a basic routing rule - ready for backend members to be
attached.

## Usage

```hcl
module "application_gateway" {
  source = "github.com/moveeeax/terraform-azurerm-application-gateway"

  name                = "prod-appgw"
  resource_group_name = "prod-rg"
  location            = "eastus"

  subnet_id            = module.appgw_subnet.id
  public_ip_address_id = azurerm_public_ip.appgw.id

  tags = {
    Environment = "production"
    ManagedBy   = "terraform"
  }
}
```

A runnable example lives in [`examples/basic`](examples/basic).

## Requirements

| Name      | Version  |
|-----------|----------|
| terraform | >= 1.5   |
| azurerm   | >= 3.0   |

## Inputs

| Name                   | Description                                                            | Type          | Default         | Required |
|------------------------|------------------------------------------------------------------------|---------------|-----------------|:--------:|
| `name`                 | Name of the application gateway.                                       | `string`      | n/a             |   yes    |
| `resource_group_name`  | Name of the resource group in which to create the application gateway. | `string`      | n/a             |   yes    |
| `location`             | Azure region in which to create the application gateway.               | `string`      | n/a             |   yes    |
| `subnet_id`            | ID of the dedicated subnet in which the gateway is deployed.           | `string`      | n/a             |   yes    |
| `public_ip_address_id` | ID of the public IP address used for the gateway's frontend.           | `string`      | n/a             |   yes    |
| `sku_name`             | SKU name of the application gateway.                                   | `string`      | `"Standard_v2"` |    no    |
| `sku_tier`             | SKU tier of the application gateway.                                   | `string`      | `"Standard_v2"` |    no    |
| `capacity`             | Number of fixed instances when autoscaling is not used.               | `number`      | `2`             |    no    |
| `frontend_port`        | Port exposed on the gateway's frontend listener.                      | `number`      | `80`            |    no    |
| `backend_port`         | Port used to reach the backend pool members.                          | `number`      | `80`            |    no    |
| `request_timeout`      | Request timeout in seconds for backend HTTP settings.                 | `number`      | `60`            |    no    |
| `tags`                 | Map of tags applied to the application gateway.                       | `map(string)` | `{}`            |    no    |

## Outputs

| Name                      | Description                                     |
|---------------------------|-------------------------------------------------|
| `id`                      | ID of the application gateway.                  |
| `name`                    | Name of the application gateway.                |
| `backend_address_pool_id` | ID of the gateway's backend address pool.       |

## License

[MIT](LICENSE)
