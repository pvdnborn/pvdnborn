source "null" "vandenBornIT-Win2019" {
    communicator                           = "winrm"
    winrm_host                             = var.winrm_host
    winrm_insecure                         = "true"
    winrm_password                         = var.winrm_password
    winrm_timeout                          = "3m"
    winrm_use_ssl                          = var.winrm_use_ssl
    winrm_port                             = var.winrm_port
    winrm_username                         = var.winrm_username
}

build {
    sources = ["sources.null.vandenBornIT-Win2019"]

    provisioner "windows-restart" {}

    #Shutdown Builder VM as last step of provisioners
    provisioner "windows-shell" {
        inline = ["shutdown /s /t 30 /f"]
    }

    #Continue with Create-XSSnapshot as next step on your pipeline
}