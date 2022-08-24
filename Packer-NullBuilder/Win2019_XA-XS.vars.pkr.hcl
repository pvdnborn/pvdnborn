variable "winrm_password" {
  type      = string
  sensitive = true
}

variable "winrm_username" {
  type    = string
}

variable "winrm_host" {
  type    = string
}

variable "winrm_port" {
    type = string
}

variable "winrm_use_ssl" {
    type = string
}