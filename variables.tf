variable "name" {
  description = "Name of the application gateway."
  type        = string
}

variable "resource_group_name" {
  description = "Name of the resource group in which to create the application gateway."
  type        = string
}

variable "location" {
  description = "Azure region in which to create the application gateway."
  type        = string
}

variable "subnet_id" {
  description = "ID of the dedicated subnet in which the application gateway is deployed."
  type        = string
}

variable "public_ip_address_id" {
  description = "ID of the public IP address used for the gateway's frontend."
  type        = string
}

variable "sku_name" {
  description = "SKU name of the application gateway. Must match sku_tier. Only the v2 SKUs are supported; the v1 SKUs are retired in Azure and rejected by azurerm 4.x."
  type        = string
  default     = "Standard_v2"

  validation {
    condition     = contains(["Standard_v2", "WAF_v2"], var.sku_name)
    error_message = "sku_name must be one of: Standard_v2, WAF_v2."
  }
}

variable "sku_tier" {
  description = "SKU tier of the application gateway. Must match sku_name. Setting WAF_v2 turns on the web application firewall."
  type        = string
  default     = "Standard_v2"

  validation {
    condition     = contains(["Standard_v2", "WAF_v2"], var.sku_tier)
    error_message = "sku_tier must be one of: Standard_v2, WAF_v2."
  }
}

variable "capacity" {
  description = "Number of fixed instances for the gateway when autoscaling is not used."
  type        = number
  default     = 2

  validation {
    condition     = var.capacity >= 1 && var.capacity <= 125 && floor(var.capacity) == var.capacity
    error_message = "capacity must be a whole number between 1 and 125."
  }
}

variable "frontend_port" {
  description = "Port exposed on the gateway's plain HTTP frontend listener."
  type        = number
  default     = 80

  validation {
    condition     = var.frontend_port >= 1 && var.frontend_port <= 65535
    error_message = "frontend_port must be between 1 and 65535."
  }
}

variable "https_port" {
  description = "Port exposed on the gateway's HTTPS frontend listener. Only used when a certificate is supplied."
  type        = number
  default     = 443

  validation {
    condition     = var.https_port >= 1 && var.https_port <= 65535
    error_message = "https_port must be between 1 and 65535."
  }
}

variable "backend_port" {
  description = "Port used to reach the backend pool members."
  type        = number
  default     = 80

  validation {
    condition     = var.backend_port >= 1 && var.backend_port <= 65535
    error_message = "backend_port must be between 1 and 65535."
  }
}

variable "backend_protocol" {
  description = "Protocol the gateway speaks to the backend pool members. Defaults to Http, which is unencrypted on the wire between the gateway and the backends; set it to Https for end-to-end TLS (and set backend_port accordingly)."
  type        = string
  default     = "Http"

  validation {
    condition     = contains(["Http", "Https"], var.backend_protocol)
    error_message = "backend_protocol must be one of: Http, Https."
  }
}

variable "request_timeout" {
  description = "Request timeout in seconds for backend HTTP settings."
  type        = number
  default     = 60

  validation {
    condition     = var.request_timeout >= 1 && var.request_timeout <= 86400
    error_message = "request_timeout must be between 1 and 86400 seconds."
  }
}

variable "ssl_policy_type" {
  description = "SSL policy type. Predefined selects one of Azure's named policies; CustomV2 selects a minimum protocol version directly."
  type        = string
  default     = "Predefined"

  validation {
    condition     = contains(["Predefined", "CustomV2"], var.ssl_policy_type)
    error_message = "ssl_policy_type must be one of: Predefined, CustomV2."
  }
}

variable "ssl_policy_name" {
  description = "Predefined SSL policy applied when ssl_policy_type is Predefined. Only the policies with a TLS 1.2 floor are accepted: AppGwSslPolicy20150501 and AppGwSslPolicy20170401 still negotiate TLS 1.0/1.1."
  type        = string
  default     = "AppGwSslPolicy20220101"

  validation {
    condition = contains([
      "AppGwSslPolicy20170401S",
      "AppGwSslPolicy20220101",
      "AppGwSslPolicy20220101S",
    ], var.ssl_policy_name)
    error_message = "ssl_policy_name must be one of: AppGwSslPolicy20170401S, AppGwSslPolicy20220101, AppGwSslPolicy20220101S. The TLS 1.0/1.1 policies are not supported by this module."
  }
}

variable "ssl_policy_min_protocol_version" {
  description = "Minimum TLS version applied when ssl_policy_type is CustomV2."
  type        = string
  default     = "TLSv1_2"

  validation {
    condition     = contains(["TLSv1_2", "TLSv1_3"], var.ssl_policy_min_protocol_version)
    error_message = "ssl_policy_min_protocol_version must be one of: TLSv1_2, TLSv1_3. TLS 1.0 and 1.1 are not supported by this module."
  }
}

variable "ssl_certificate_key_vault_secret_id" {
  description = "Key Vault secret ID of the certificate served by the HTTPS listener. Supplying this (or ssl_certificate_data) is what creates the HTTPS listener. Requires identity_ids."
  type        = string
  default     = null
}

variable "ssl_certificate_data" {
  description = "Base64-encoded PFX certificate served by the HTTPS listener, as an alternative to ssl_certificate_key_vault_secret_id. Prefer Key Vault: this value is stored in state."
  type        = string
  default     = null
  sensitive   = true
}

variable "ssl_certificate_password" {
  description = "Password for ssl_certificate_data."
  type        = string
  default     = null
  sensitive   = true
}

variable "https_host_name" {
  description = "Host name the HTTPS listener answers for. Leave null to answer for any host."
  type        = string
  default     = null
}

variable "redirect_http_to_https" {
  description = "When an HTTPS listener exists, make the plain HTTP listener issue a permanent redirect to it instead of serving the backend. Set to false to serve both in parallel."
  type        = bool
  default     = true
}

variable "identity_ids" {
  description = "User-assigned managed identity ID attached to the gateway, as a single-element list. Required when ssl_certificate_key_vault_secret_id is used. Azure supports at most one managed identity per Application Gateway; a longer list is rejected at plan time instead of failing obscurely on apply."
  type        = list(string)
  default     = []

  validation {
    condition     = length(var.identity_ids) <= 1
    error_message = "identity_ids can contain at most one identity: Azure Application Gateway supports only a single user-assigned managed identity."
  }
}

variable "firewall_policy_id" {
  description = "ID of a standalone azurerm_web_application_firewall_policy to attach. Requires sku_tier WAF_v2, and replaces the inline WAF configuration built from the waf_* variables."
  type        = string
  default     = null
}

variable "waf_firewall_mode" {
  description = "Mode of the inline WAF configuration on a WAF_v2 gateway. Detection only logs matches; Prevention actually blocks them."
  type        = string
  default     = "Prevention"

  validation {
    condition     = contains(["Detection", "Prevention"], var.waf_firewall_mode)
    error_message = "waf_firewall_mode must be one of: Detection, Prevention."
  }
}

variable "waf_rule_set_type" {
  description = "Rule set type of the inline WAF configuration. Attach a firewall_policy_id instead if you need the bot manager rule sets."
  type        = string
  default     = "OWASP"

  validation {
    condition     = var.waf_rule_set_type == "OWASP"
    error_message = "waf_rule_set_type must be OWASP; use firewall_policy_id for other rule set types."
  }
}

variable "waf_rule_set_version" {
  description = "Rule set version of the inline WAF configuration."
  type        = string
  default     = "3.2"

  validation {
    condition     = contains(["2.2.9", "3.0", "3.1", "3.2"], var.waf_rule_set_version)
    error_message = "waf_rule_set_version must be one of: 2.2.9, 3.0, 3.1, 3.2."
  }
}

variable "tags" {
  description = "Map of tags applied to the application gateway."
  type        = map(string)
  default     = {}
}
