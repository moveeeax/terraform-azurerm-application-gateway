locals {
  backend_address_pool_name       = "${var.name}-beap"
  frontend_port_name              = "${var.name}-feport"
  frontend_https_port_name        = "${var.name}-feport-https"
  frontend_ip_configuration_name  = "${var.name}-feip"
  http_setting_name               = "${var.name}-be-htst"
  listener_name                   = "${var.name}-httplstn"
  https_listener_name             = "${var.name}-httpslstn"
  request_routing_rule_name       = "${var.name}-rqrt"
  https_request_routing_rule_name = "${var.name}-rqrt-https"
  redirect_configuration_name     = "${var.name}-rdrcfg"
  ssl_certificate_name            = "${var.name}-sslcert"

  # An HTTPS listener is only possible once a certificate has been supplied,
  # either from Key Vault or inline as PFX data.
  https_enabled = var.ssl_certificate_key_vault_secret_id != null || var.ssl_certificate_data != null

  # When HTTPS is available the plain HTTP listener redirects instead of
  # serving the backend, so nothing is ever answered in the clear.
  redirect_http_to_https = local.https_enabled && var.redirect_http_to_https

  # An inline `waf_configuration` block and a standalone WAF policy are
  # mutually exclusive; the policy wins when both could apply.
  waf_configuration_enabled = var.sku_tier == "WAF_v2" && var.firewall_policy_id == null

  routing_rules = concat(
    [{
      name                        = local.request_routing_rule_name
      priority                    = 100
      http_listener_name          = local.listener_name
      backend_address_pool_name   = local.redirect_http_to_https ? null : local.backend_address_pool_name
      backend_http_settings_name  = local.redirect_http_to_https ? null : local.http_setting_name
      redirect_configuration_name = local.redirect_http_to_https ? local.redirect_configuration_name : null
    }],
    local.https_enabled ? [{
      name                        = local.https_request_routing_rule_name
      priority                    = 110
      http_listener_name          = local.https_listener_name
      backend_address_pool_name   = local.backend_address_pool_name
      backend_http_settings_name  = local.http_setting_name
      redirect_configuration_name = null
    }] : []
  )
}

resource "azurerm_application_gateway" "this" {
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location
  firewall_policy_id  = var.firewall_policy_id

  sku {
    name     = var.sku_name
    tier     = var.sku_tier
    capacity = var.capacity
  }

  # Reading a certificate out of Key Vault requires a user-assigned identity
  # that has been granted access to that vault.
  dynamic "identity" {
    for_each = length(var.identity_ids) > 0 ? [1] : []

    content {
      type         = "UserAssigned"
      identity_ids = var.identity_ids
    }
  }

  gateway_ip_configuration {
    name      = "${var.name}-ipcfg"
    subnet_id = var.subnet_id
  }

  frontend_port {
    name = local.frontend_port_name
    port = var.frontend_port
  }

  dynamic "frontend_port" {
    for_each = local.https_enabled ? [1] : []

    content {
      name = local.frontend_https_port_name
      port = var.https_port
    }
  }

  frontend_ip_configuration {
    name                 = local.frontend_ip_configuration_name
    public_ip_address_id = var.public_ip_address_id
  }

  backend_address_pool {
    name = local.backend_address_pool_name
  }

  backend_http_settings {
    name                  = local.http_setting_name
    cookie_based_affinity = "Disabled"
    port                  = var.backend_port
    protocol              = var.backend_protocol
    request_timeout       = var.request_timeout
  }

  dynamic "ssl_certificate" {
    for_each = local.https_enabled ? [1] : []

    content {
      name                = local.ssl_certificate_name
      key_vault_secret_id = var.ssl_certificate_key_vault_secret_id
      data                = var.ssl_certificate_data
      password            = var.ssl_certificate_password
    }
  }

  # TLS 1.0 and TLS 1.1 are dead. Azure's implicit default policy
  # (AppGwSslPolicy20150501) still negotiates them, so the policy is always
  # set explicitly rather than left to the service default.
  ssl_policy {
    policy_type          = var.ssl_policy_type
    policy_name          = var.ssl_policy_type == "Predefined" ? var.ssl_policy_name : null
    min_protocol_version = var.ssl_policy_type == "Predefined" ? null : var.ssl_policy_min_protocol_version
  }

  http_listener {
    name                           = local.listener_name
    frontend_ip_configuration_name = local.frontend_ip_configuration_name
    frontend_port_name             = local.frontend_port_name
    protocol                       = "Http"
  }

  dynamic "http_listener" {
    for_each = local.https_enabled ? [1] : []

    content {
      name                           = local.https_listener_name
      frontend_ip_configuration_name = local.frontend_ip_configuration_name
      frontend_port_name             = local.frontend_https_port_name
      protocol                       = "Https"
      ssl_certificate_name           = local.ssl_certificate_name
      host_name                      = var.https_host_name
    }
  }

  dynamic "redirect_configuration" {
    for_each = local.redirect_http_to_https ? [1] : []

    content {
      name                 = local.redirect_configuration_name
      redirect_type        = "Permanent"
      target_listener_name = local.https_listener_name
      include_path         = true
      include_query_string = true
    }
  }

  dynamic "request_routing_rule" {
    for_each = { for rule in local.routing_rules : rule.name => rule }

    content {
      name                        = request_routing_rule.value.name
      priority                    = request_routing_rule.value.priority
      rule_type                   = "Basic"
      http_listener_name          = request_routing_rule.value.http_listener_name
      backend_address_pool_name   = request_routing_rule.value.backend_address_pool_name
      backend_http_settings_name  = request_routing_rule.value.backend_http_settings_name
      redirect_configuration_name = request_routing_rule.value.redirect_configuration_name
    }
  }

  # A WAF_v2 gateway with neither an inline WAF configuration nor a WAF policy
  # attached is rejected by the API, so one is always emitted for that tier.
  dynamic "waf_configuration" {
    for_each = local.waf_configuration_enabled ? [1] : []

    content {
      enabled          = true
      firewall_mode    = var.waf_firewall_mode
      rule_set_type    = var.waf_rule_set_type
      rule_set_version = var.waf_rule_set_version
    }
  }

  tags = var.tags

  lifecycle {
    precondition {
      condition     = var.sku_name == var.sku_tier
      error_message = "sku_name and sku_tier must match; got sku_name=${var.sku_name} and sku_tier=${var.sku_tier}."
    }

    precondition {
      condition     = var.firewall_policy_id == null || var.sku_tier == "WAF_v2"
      error_message = "firewall_policy_id can only be attached to a WAF_v2 gateway; sku_tier is ${var.sku_tier}."
    }

    precondition {
      condition     = var.ssl_certificate_key_vault_secret_id == null || var.ssl_certificate_data == null
      error_message = "Set either ssl_certificate_key_vault_secret_id or ssl_certificate_data, not both."
    }

    precondition {
      condition     = var.ssl_certificate_key_vault_secret_id == null || length(var.identity_ids) > 0
      error_message = "ssl_certificate_key_vault_secret_id requires identity_ids: the gateway needs a user-assigned identity with access to the key vault."
    }

    precondition {
      condition     = !local.https_enabled || var.frontend_port != var.https_port
      error_message = "frontend_port and https_port must differ; got ${var.frontend_port} for both."
    }
  }
}
