# terraform-azurerm-application-gateway

Terraform module that manages an [Azure](https://azure.microsoft.com/)
Application Gateway. It wires up a complete v2 gateway - gateway IP
configuration, frontend ports and public IP, a backend pool, HTTP settings,
listeners and routing rules - ready for backend members to be attached.

The defaults aim to be safe rather than minimal:

- The SSL policy is always set explicitly. Azure's implicit default
  (`AppGwSslPolicy20150501`) still negotiates TLS 1.0 and 1.1; this module
  defaults to `AppGwSslPolicy20220101` and refuses to configure a policy with a
  floor below TLS 1.2.
- Selecting `sku_tier = "WAF_v2"` actually turns a WAF on, in **Prevention**
  mode (Detection only logs, it does not block). A WAF-tier gateway with no WAF
  configuration and no firewall policy is rejected by Azure.
- Supplying a certificate adds an HTTPS listener and, by default, turns the
  plain HTTP listener into a permanent redirect to it.
- `sku_name`/`sku_tier` mismatches, Key Vault certificates without an identity,
  and firewall policies on non-WAF tiers fail at plan time instead of at apply.

## Usage

Minimal, plain HTTP:

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

WAF-enabled, TLS-terminating, redirecting HTTP to HTTPS:

```hcl
module "application_gateway" {
  source = "github.com/moveeeax/terraform-azurerm-application-gateway"

  name                = "prod-appgw"
  resource_group_name = "prod-rg"
  location            = "eastus"

  subnet_id            = module.appgw_subnet.id
  public_ip_address_id = azurerm_public_ip.appgw.id

  sku_name = "WAF_v2"
  sku_tier = "WAF_v2"

  # Reading the certificate out of Key Vault needs a user-assigned identity
  # with get access to the vault's secrets.
  identity_ids                        = [azurerm_user_assigned_identity.appgw.id]
  ssl_certificate_key_vault_secret_id = azurerm_key_vault_certificate.app.versionless_secret_id
  https_host_name                     = "www.example.com"

  # End-to-end TLS instead of plain HTTP on the gateway-to-backend hop.
  backend_protocol = "Https"
  backend_port     = 443

  tags = {
    Environment = "production"
    ManagedBy   = "terraform"
  }
}
```

Runnable examples live in [`examples/basic`](examples/basic) and
[`examples/complete`](examples/complete).

## HTTPS and redirects

The HTTPS listener is created as soon as either
`ssl_certificate_key_vault_secret_id` or `ssl_certificate_data` is set. When it
exists:

- `frontend_port` (default `80`) serves the HTTP listener and `https_port`
  (default `443`) serves the HTTPS listener; the two must differ.
- With `redirect_http_to_https = true` (the default) the HTTP listener is wired
  to a permanent redirect that preserves path and query string, and does not
  reach the backend at all.
- With `redirect_http_to_https = false` both listeners serve the backend pool.

Without a certificate the module behaves as before: a single HTTP listener
routing straight to the backend pool.

## Web application firewall

`sku_name`/`sku_tier` of `WAF_v2` emits an inline `waf_configuration` with
`enabled = true` and `firewall_mode = var.waf_firewall_mode` (default
`Prevention`). Setting `firewall_policy_id` attaches a standalone
`azurerm_web_application_firewall_policy` instead, and the inline configuration
is dropped - the two are mutually exclusive in Azure.

## Requirements

| Name      | Version  |
|-----------|----------|
| terraform | >= 1.5   |
| azurerm   | >= 3.0   |

The test suite under [`tests/`](tests) additionally needs Terraform or
OpenTofu >= 1.7 for `mock_provider`; the module itself does not.

## Inputs

| Name                                  | Description                                                                                                | Type           | Default                   | Required |
|---------------------------------------|------------------------------------------------------------------------------------------------------------|----------------|---------------------------|:--------:|
| `name`                                | Name of the application gateway.                                                                            | `string`       | n/a                       |   yes    |
| `resource_group_name`                 | Name of the resource group in which to create the application gateway.                                      | `string`       | n/a                       |   yes    |
| `location`                            | Azure region in which to create the application gateway.                                                    | `string`       | n/a                       |   yes    |
| `subnet_id`                           | ID of the dedicated subnet in which the gateway is deployed.                                                | `string`       | n/a                       |   yes    |
| `public_ip_address_id`                | ID of the public IP address used for the gateway's frontend.                                                | `string`       | n/a                       |   yes    |
| `sku_name`                            | SKU name. One of `Standard_v2`, `WAF_v2`; must match `sku_tier`.                                            | `string`       | `"Standard_v2"`           |    no    |
| `sku_tier`                            | SKU tier. One of `Standard_v2`, `WAF_v2`; must match `sku_name`.                                            | `string`       | `"Standard_v2"`           |    no    |
| `capacity`                            | Number of fixed instances when autoscaling is not used (1-125).                                             | `number`       | `2`                       |    no    |
| `frontend_port`                       | Port exposed on the plain HTTP frontend listener.                                                           | `number`       | `80`                      |    no    |
| `https_port`                          | Port exposed on the HTTPS frontend listener. Only used when a certificate is supplied.                      | `number`       | `443`                     |    no    |
| `backend_port`                        | Port used to reach the backend pool members.                                                                | `number`       | `80`                      |    no    |
| `backend_protocol`                    | Protocol spoken to the backend pool. `Http` is unencrypted on that hop; `Https` gives end-to-end TLS.       | `string`       | `"Http"`                  |    no    |
| `request_timeout`                     | Request timeout in seconds for backend HTTP settings (1-86400).                                             | `number`       | `60`                      |    no    |
| `ssl_policy_type`                     | One of `Predefined`, `CustomV2`.                                                                            | `string`       | `"Predefined"`            |    no    |
| `ssl_policy_name`                     | Predefined policy used when `ssl_policy_type` is `Predefined`. Only TLS 1.2+ policies are accepted.         | `string`       | `"AppGwSslPolicy20220101"`|    no    |
| `ssl_policy_min_protocol_version`     | Minimum TLS version used when `ssl_policy_type` is `CustomV2`. One of `TLSv1_2`, `TLSv1_3`.                 | `string`       | `"TLSv1_2"`               |    no    |
| `ssl_certificate_key_vault_secret_id` | Key Vault secret ID of the HTTPS listener certificate. Requires `identity_ids`.                             | `string`       | `null`                    |    no    |
| `ssl_certificate_data`                | Base64-encoded PFX certificate, as an alternative to the Key Vault secret ID. Stored in state.              | `string`       | `null`                    |    no    |
| `ssl_certificate_password`            | Password for `ssl_certificate_data`.                                                                        | `string`       | `null`                    |    no    |
| `https_host_name`                     | Host name the HTTPS listener answers for.                                                                   | `string`       | `null`                    |    no    |
| `redirect_http_to_https`              | Redirect the HTTP listener to HTTPS when an HTTPS listener exists.                                          | `bool`         | `true`                    |    no    |
| `identity_ids`                        | User-assigned managed identity IDs attached to the gateway.                                                 | `list(string)` | `[]`                      |    no    |
| `firewall_policy_id`                  | Standalone WAF policy to attach. Requires `sku_tier = "WAF_v2"` and replaces the inline WAF configuration.  | `string`       | `null`                    |    no    |
| `waf_firewall_mode`                   | Inline WAF mode. `Detection` only logs; `Prevention` blocks.                                                | `string`       | `"Prevention"`            |    no    |
| `waf_rule_set_type`                   | Inline WAF rule set type.                                                                                   | `string`       | `"OWASP"`                 |    no    |
| `waf_rule_set_version`                | Inline WAF rule set version. One of `2.2.9`, `3.0`, `3.1`, `3.2`.                                           | `string`       | `"3.2"`                   |    no    |
| `tags`                                | Map of tags applied to the application gateway.                                                             | `map(string)`  | `{}`                      |    no    |

## Outputs

| Name                      | Description                                     |
|---------------------------|-------------------------------------------------|
| `id`                      | ID of the application gateway.                  |
| `name`                    | Name of the application gateway.                |
| `backend_address_pool_id` | ID of the gateway's backend address pool.       |

## Development

```sh
terraform fmt -recursive
terraform init -backend=false && terraform validate
terraform test
tflint --chdir=.
```

## License

[MIT](LICENSE)
