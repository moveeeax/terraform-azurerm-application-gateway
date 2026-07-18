output "id" {
  description = "ID of the application gateway."
  value       = azurerm_application_gateway.this.id
}

output "name" {
  description = "Name of the application gateway."
  value       = azurerm_application_gateway.this.name
}

output "backend_address_pool_id" {
  description = "ID of the gateway's backend address pool, for associating backend members."
  value       = one(azurerm_application_gateway.this.backend_address_pool[*].id)
}
