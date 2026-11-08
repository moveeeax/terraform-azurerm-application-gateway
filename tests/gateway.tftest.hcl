# Requires Terraform >= 1.7 / OpenTofu >= 1.7 for `mock_provider`.
# The module itself still supports >= 1.5 - do not raise required_version for
# these tests.
mock_provider "azurerm" {}

variables {
  name                 = "test-appgw"
  resource_group_name  = "test-rg"
  location             = "eastus"
  subnet_id            = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test-rg/providers/Microsoft.Network/virtualNetworks/vnet/subnets/appgw"
  public_ip_address_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test-rg/providers/Microsoft.Network/publicIPAddresses/pip"
}

run "defaults_pin_tls_12_and_leave_waf_off" {
  assert {
    condition     = azurerm_application_gateway.this.ssl_policy[0].policy_type == "Predefined"
    error_message = "The gateway must set an explicit SSL policy instead of inheriting Azure's TLS 1.0 default."
  }

  assert {
    condition     = azurerm_application_gateway.this.ssl_policy[0].policy_name == "AppGwSslPolicy20220101"
    error_message = "The default predefined SSL policy must have a TLS 1.2 floor."
  }

  assert {
    condition     = length(azurerm_application_gateway.this.waf_configuration) == 0
    error_message = "A Standard_v2 gateway must not carry a WAF configuration."
  }

  assert {
    condition     = length(azurerm_application_gateway.this.http_listener) == 1
    error_message = "Without a certificate the gateway has a single HTTP listener."
  }

  assert {
    condition     = length(azurerm_application_gateway.this.redirect_configuration) == 0
    error_message = "Without an HTTPS listener there is nothing to redirect to."
  }

  assert {
    condition     = one([for r in azurerm_application_gateway.this.request_routing_rule : r.backend_address_pool_name]) == "test-appgw-beap"
    error_message = "The single routing rule must serve the backend pool."
  }
}

run "custom_v2_ssl_policy_uses_min_protocol_version" {
  variables {
    ssl_policy_type                 = "CustomV2"
    ssl_policy_min_protocol_version = "TLSv1_3"
  }

  assert {
    condition     = azurerm_application_gateway.this.ssl_policy[0].min_protocol_version == "TLSv1_3"
    error_message = "CustomV2 must pass min_protocol_version through."
  }

  assert {
    condition     = azurerm_application_gateway.this.ssl_policy[0].policy_name == null
    error_message = "policy_name only applies to the Predefined policy type."
  }
}

run "rejects_tls_10_ssl_policy" {
  command = plan

  variables {
    ssl_policy_name = "AppGwSslPolicy20150501"
  }

  expect_failures = [var.ssl_policy_name]
}

run "rejects_tls_11_min_protocol_version" {
  command = plan

  variables {
    ssl_policy_type                 = "CustomV2"
    ssl_policy_min_protocol_version = "TLSv1_1"
  }

  expect_failures = [var.ssl_policy_min_protocol_version]
}

run "waf_tier_gets_a_prevention_mode_waf" {
  variables {
    sku_name = "WAF_v2"
    sku_tier = "WAF_v2"
  }

  assert {
    condition     = azurerm_application_gateway.this.waf_configuration[0].enabled
    error_message = "A WAF_v2 gateway must emit an enabled WAF configuration."
  }

  assert {
    condition     = azurerm_application_gateway.this.waf_configuration[0].firewall_mode == "Prevention"
    error_message = "The WAF must default to Prevention; Detection only logs."
  }

  assert {
    condition     = azurerm_application_gateway.this.waf_configuration[0].rule_set_version == "3.2"
    error_message = "The WAF must default to OWASP 3.2."
  }
}

run "rejects_unknown_waf_firewall_mode" {
  command = plan

  variables {
    sku_name          = "WAF_v2"
    sku_tier          = "WAF_v2"
    waf_firewall_mode = "Detect"
  }

  expect_failures = [var.waf_firewall_mode]
}

run "firewall_policy_replaces_the_inline_waf_configuration" {
  variables {
    sku_name           = "WAF_v2"
    sku_tier           = "WAF_v2"
    firewall_policy_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test-rg/providers/Microsoft.Network/applicationGatewayWebApplicationFirewallPolicies/policy"
  }

  assert {
    condition     = length(azurerm_application_gateway.this.waf_configuration) == 0
    error_message = "An inline WAF configuration and a WAF policy are mutually exclusive."
  }

  assert {
    condition     = azurerm_application_gateway.this.firewall_policy_id != null
    error_message = "The WAF policy must be attached to the gateway."
  }
}

run "rejects_firewall_policy_on_a_standard_tier_gateway" {
  command = plan

  variables {
    firewall_policy_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test-rg/providers/Microsoft.Network/applicationGatewayWebApplicationFirewallPolicies/policy"
  }

  expect_failures = [azurerm_application_gateway.this]
}

run "rejects_mismatched_sku_name_and_tier" {
  command = plan

  variables {
    sku_name = "WAF_v2"
  }

  expect_failures = [azurerm_application_gateway.this]
}

run "rejects_retired_v1_sku" {
  command = plan

  variables {
    sku_name = "Standard_Medium"
    sku_tier = "Standard"
  }

  expect_failures = [var.sku_name, var.sku_tier]
}

run "certificate_creates_an_https_listener_and_redirects_http" {
  variables {
    ssl_certificate_key_vault_secret_id = "https://test-kv.vault.azure.net/secrets/appgw-cert"
    identity_ids                        = ["/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test-rg/providers/Microsoft.ManagedIdentity/userAssignedIdentities/appgw"]
  }

  assert {
    condition     = length(azurerm_application_gateway.this.http_listener) == 2
    error_message = "Supplying a certificate must add an HTTPS listener."
  }

  assert {
    condition     = one([for l in azurerm_application_gateway.this.http_listener : l.protocol if l.name == "test-appgw-httpslstn"]) == "Https"
    error_message = "The second listener must speak HTTPS."
  }

  assert {
    condition     = one([for p in azurerm_application_gateway.this.frontend_port : p.port if p.name == "test-appgw-feport-https"]) == 443
    error_message = "The HTTPS listener must be bound to the HTTPS frontend port."
  }

  assert {
    condition     = one([for r in azurerm_application_gateway.this.redirect_configuration : r.redirect_type]) == "Permanent"
    error_message = "HTTP must be permanently redirected to HTTPS."
  }

  assert {
    condition     = one([for r in azurerm_application_gateway.this.request_routing_rule : r.redirect_configuration_name if r.name == "test-appgw-rqrt"]) == "test-appgw-rdrcfg"
    error_message = "The HTTP routing rule must point at the redirect, not at the backend."
  }

  assert {
    condition     = one([for r in azurerm_application_gateway.this.request_routing_rule : r.backend_address_pool_name if r.name == "test-appgw-rqrt"]) == null
    error_message = "The redirecting HTTP rule must not also serve the backend."
  }

  assert {
    condition     = one([for r in azurerm_application_gateway.this.request_routing_rule : r.backend_address_pool_name if r.name == "test-appgw-rqrt-https"]) == "test-appgw-beap"
    error_message = "The HTTPS routing rule must serve the backend pool."
  }

  assert {
    condition     = azurerm_application_gateway.this.identity[0].type == "UserAssigned"
    error_message = "A Key Vault certificate needs a user-assigned identity."
  }
}

run "redirect_can_be_turned_off_to_serve_both_listeners" {
  variables {
    ssl_certificate_key_vault_secret_id = "https://test-kv.vault.azure.net/secrets/appgw-cert"
    identity_ids                        = ["/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test-rg/providers/Microsoft.ManagedIdentity/userAssignedIdentities/appgw"]
    redirect_http_to_https              = false
  }

  assert {
    condition     = length(azurerm_application_gateway.this.redirect_configuration) == 0
    error_message = "redirect_http_to_https = false must not create a redirect configuration."
  }

  assert {
    condition     = one([for r in azurerm_application_gateway.this.request_routing_rule : r.backend_address_pool_name if r.name == "test-appgw-rqrt"]) == "test-appgw-beap"
    error_message = "With the redirect off the HTTP rule serves the backend again."
  }
}

run "key_vault_certificate_without_an_identity_is_rejected" {
  command = plan

  variables {
    ssl_certificate_key_vault_secret_id = "https://test-kv.vault.azure.net/secrets/appgw-cert"
  }

  expect_failures = [azurerm_application_gateway.this]
}

run "rejects_more_than_one_identity_id" {
  command = plan

  variables {
    ssl_certificate_key_vault_secret_id = "https://test-kv.vault.azure.net/secrets/appgw-cert"
    identity_ids = [
      "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test-rg/providers/Microsoft.ManagedIdentity/userAssignedIdentities/appgw-1",
      "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test-rg/providers/Microsoft.ManagedIdentity/userAssignedIdentities/appgw-2",
    ]
  }

  expect_failures = [var.identity_ids]
}

run "backend_protocol_can_be_switched_to_https" {
  variables {
    backend_protocol = "Https"
    backend_port     = 443
  }

  assert {
    condition     = one([for s in azurerm_application_gateway.this.backend_http_settings : s.protocol]) == "Https"
    error_message = "backend_protocol must reach the backend HTTP settings."
  }
}

run "rejects_unknown_backend_protocol" {
  command = plan

  variables {
    backend_protocol = "TCP"
  }

  expect_failures = [var.backend_protocol]
}

# The individual runs above each flip one optional feature at a time. This one
# turns on every optional feature together - WAF, a Key Vault certificate with
# its redirect, and end-to-end TLS to the backend - to catch interactions that
# only show up when the flags combine (e.g. one feature's dynamic block
# accidentally suppressing another's).
run "waf_https_redirect_and_backend_tls_all_work_together" {
  variables {
    sku_name = "WAF_v2"
    sku_tier = "WAF_v2"

    waf_firewall_mode    = "Prevention"
    waf_rule_set_version = "3.2"

    ssl_certificate_key_vault_secret_id = "https://test-kv.vault.azure.net/secrets/appgw-cert"
    identity_ids                        = ["/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test-rg/providers/Microsoft.ManagedIdentity/userAssignedIdentities/appgw"]
    https_host_name                     = "www.example.com"

    backend_protocol = "Https"
    backend_port     = 443
  }

  assert {
    condition     = azurerm_application_gateway.this.waf_configuration[0].enabled
    error_message = "The WAF must stay enabled when combined with HTTPS and backend TLS."
  }

  assert {
    condition     = length(azurerm_application_gateway.this.http_listener) == 2
    error_message = "A certificate must still add the HTTPS listener when the WAF is also on."
  }

  assert {
    condition     = one([for r in azurerm_application_gateway.this.redirect_configuration : r.redirect_type]) == "Permanent"
    error_message = "HTTP must still redirect to HTTPS when the WAF is also on."
  }

  assert {
    condition     = one([for s in azurerm_application_gateway.this.backend_http_settings : s.protocol]) == "Https"
    error_message = "The backend hop must still use HTTPS when the WAF and gateway HTTPS are also on."
  }

  assert {
    condition     = one([for r in azurerm_application_gateway.this.request_routing_rule : r.backend_address_pool_name if r.name == "test-appgw-rqrt-https"]) == "test-appgw-beap"
    error_message = "The HTTPS routing rule must still serve the backend pool with every optional feature enabled."
  }
}

run "defaults_keep_the_azure_default_probe" {
  command = plan

  assert {
    condition     = length(azurerm_application_gateway.this.probe) == 0
    error_message = "No custom probe may be emitted unless probe is set."
  }

  assert {
    condition     = one([for s in azurerm_application_gateway.this.backend_http_settings : s.probe_name]) == null
    error_message = "The backend HTTP settings must not reference a probe by default."
  }

  assert {
    condition     = one([for s in azurerm_application_gateway.this.backend_http_settings : s.host_name]) == null
    error_message = "The backend HTTP settings must not override the Host header by default."
  }

  assert {
    condition     = one([for s in azurerm_application_gateway.this.backend_http_settings : s.pick_host_name_from_backend_address]) == false
    error_message = "The backend HTTP settings must not pick the backend host name by default."
  }
}

run "probe_with_backend_host_from_address" {
  variables {
    backend_pick_host_name_from_backend_address = true

    probe = {
      path = "/healthz"
    }
  }

  assert {
    condition     = one([for p in azurerm_application_gateway.this.probe : p.name]) == "test-appgw-probe"
    error_message = "Setting probe must emit one probe named after the gateway."
  }

  assert {
    condition     = one([for s in azurerm_application_gateway.this.backend_http_settings : s.probe_name]) == "test-appgw-probe"
    error_message = "The backend HTTP settings must use the custom probe."
  }

  assert {
    condition     = one([for p in azurerm_application_gateway.this.probe : p.path]) == "/healthz"
    error_message = "probe.path must reach the probe."
  }

  assert {
    condition     = one([for p in azurerm_application_gateway.this.probe : p.protocol]) == "Http"
    error_message = "The probe protocol must default to backend_protocol."
  }

  assert {
    condition = one([for p in azurerm_application_gateway.this.probe : (
      p.interval == 30 && p.timeout == 30 && p.unhealthy_threshold == 3
    )])
    error_message = "The probe must default to a 30 s interval, 30 s timeout and 3 failures."
  }

  assert {
    condition     = one([for p in azurerm_application_gateway.this.probe : p.match[0].status_code]) == tolist(["200-399"])
    error_message = "The probe must accept 200-399 by default."
  }

  assert {
    condition     = one([for p in azurerm_application_gateway.this.probe : p.pick_host_name_from_backend_http_settings])
    error_message = "The probe must take its host from the backend HTTP settings by default."
  }

  assert {
    condition     = one([for s in azurerm_application_gateway.this.backend_http_settings : s.pick_host_name_from_backend_address])
    error_message = "backend_pick_host_name_from_backend_address must reach the backend HTTP settings."
  }
}

run "probe_with_its_own_host_over_https" {
  variables {
    backend_protocol = "Https"
    backend_port     = 443

    probe = {
      path                                      = "/status"
      host                                      = "app.internal.example.com"
      pick_host_name_from_backend_http_settings = false
      interval                                  = 15
      timeout                                   = 10
      unhealthy_threshold                       = 5
      match_status_codes                        = ["200"]
      match_body                                = "ok"
    }
  }

  assert {
    condition     = one([for p in azurerm_application_gateway.this.probe : p.host]) == "app.internal.example.com"
    error_message = "probe.host must reach the probe."
  }

  assert {
    condition     = one([for p in azurerm_application_gateway.this.probe : p.protocol]) == "Https"
    error_message = "The probe must follow backend_protocol when probe.protocol is null."
  }

  assert {
    condition     = one([for p in azurerm_application_gateway.this.probe : p.match[0].body]) == "ok"
    error_message = "probe.match_body must reach the probe."
  }

  assert {
    condition     = one([for p in azurerm_application_gateway.this.probe : p.unhealthy_threshold]) == 5
    error_message = "probe.unhealthy_threshold must reach the probe."
  }
}

run "backend_host_name_reaches_the_http_settings" {
  variables {
    backend_host_name = "app.example.com"
  }

  assert {
    condition     = one([for s in azurerm_application_gateway.this.backend_http_settings : s.host_name]) == "app.example.com"
    error_message = "backend_host_name must reach the backend HTTP settings."
  }
}

run "rejects_probe_picking_a_host_the_settings_do_not_have" {
  command = plan

  variables {
    probe = {
      path = "/healthz"
    }
  }

  expect_failures = [azurerm_application_gateway.this]
}

run "rejects_probe_with_host_and_pick_host_name" {
  command = plan

  variables {
    backend_host_name = "app.example.com"

    probe = {
      path = "/healthz"
      host = "app.example.com"
    }
  }

  expect_failures = [azurerm_application_gateway.this]
}

run "rejects_probe_without_any_host" {
  command = plan

  variables {
    probe = {
      path                                      = "/healthz"
      pick_host_name_from_backend_http_settings = false
    }
  }

  expect_failures = [azurerm_application_gateway.this]
}

run "rejects_backend_host_name_with_pick_host_name_from_backend_address" {
  command = plan

  variables {
    backend_host_name                           = "app.example.com"
    backend_pick_host_name_from_backend_address = true
  }

  expect_failures = [azurerm_application_gateway.this]
}

run "rejects_probe_path_without_leading_slash" {
  command = plan

  variables {
    backend_pick_host_name_from_backend_address = true

    probe = {
      path = "healthz"
    }
  }

  expect_failures = [var.probe]
}

run "rejects_unknown_probe_protocol" {
  command = plan

  variables {
    backend_pick_host_name_from_backend_address = true

    probe = {
      path     = "/healthz"
      protocol = "Tcp"
    }
  }

  expect_failures = [var.probe]
}

run "rejects_out_of_range_probe_unhealthy_threshold" {
  command = plan

  variables {
    backend_pick_host_name_from_backend_address = true

    probe = {
      path                = "/healthz"
      unhealthy_threshold = 21
    }
  }

  expect_failures = [var.probe]
}

run "rejects_out_of_range_probe_interval" {
  command = plan

  variables {
    backend_pick_host_name_from_backend_address = true

    probe = {
      path     = "/healthz"
      interval = 0
    }
  }

  expect_failures = [var.probe]
}

run "rejects_malformed_probe_status_code" {
  command = plan

  variables {
    backend_pick_host_name_from_backend_address = true

    probe = {
      path               = "/healthz"
      match_status_codes = ["2xx"]
    }
  }

  expect_failures = [var.probe]
}

run "rejects_empty_probe_status_codes" {
  command = plan

  variables {
    backend_pick_host_name_from_backend_address = true

    probe = {
      path               = "/healthz"
      match_status_codes = []
    }
  }

  expect_failures = [var.probe]
}
