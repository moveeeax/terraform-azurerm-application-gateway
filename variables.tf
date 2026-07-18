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
  description = "SKU name of the application gateway, e.g. Standard_v2 or WAF_v2."
  type        = string
  default     = "Standard_v2"
}

variable "sku_tier" {
  description = "SKU tier of the application gateway, e.g. Standard_v2 or WAF_v2."
  type        = string
  default     = "Standard_v2"
}

variable "capacity" {
  description = "Number of fixed instances for the gateway when autoscaling is not used."
  type        = number
  default     = 2
}

variable "frontend_port" {
  description = "Port exposed on the gateway's frontend listener."
  type        = number
  default     = 80
}

variable "backend_port" {
  description = "Port used to reach the backend pool members."
  type        = number
  default     = 80
}

variable "request_timeout" {
  description = "Request timeout in seconds for backend HTTP settings."
  type        = number
  default     = 60
}

variable "tags" {
  description = "Map of tags applied to the application gateway."
  type        = map(string)
  default     = {}
}
