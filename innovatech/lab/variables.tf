variable "pm_api_url" {
  type        = string
  description = "Proxmox API URL (e.g., https://192.168.1.100:8006/api2/json)"
}

variable "pm_api_token" {
  type        = string
  description = "Proxmox API Token (Format: user@realm!token_id=00000000-0000-0000-0000-000000000000)"
  sensitive   = true
}