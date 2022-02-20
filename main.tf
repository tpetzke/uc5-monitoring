 # IaC module to deploy a 2-Tier IaaS infrastructure in Azure
 # Tier 1: Web-Layer consisting of 2 Load Balanced Web Servers
 # Tier 2: DB-Layer with a Postgres DB
 #
 # Note: The web-site is static so there will be no actual app-db
 #       communication between the web-servers and the DB. 
 #       It is used for demo purposes only
 
# Bootstrapping Template File
data "template_file" "nginx_vm_cloud_init" {
  template = file("install-nginx.sh")
}

 terraform {

  required_version = ">=0.12"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~>2.0"
    }
  }
}

provider "azurerm" {
  features {}

}

#Create a resource group to hold all the resources
resource "azurerm_resource_group" "rg" {
  name     = "${var.env}"
  location = "${var.azure_region}"
}

#Create a LogAnalytics Workspace
resource "azurerm_log_analytics_workspace" "log_ws" {
  name                = "log-ws-uc5"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = "PerGB2018"
  retention_in_days   = 180
}

# Create the VM INsights Log Analytics Solution to collect additional metrics for VMs
resource "azurerm_log_analytics_solution" "vminsights" {
  solution_name         = "VMInsights"
  location              = azurerm_resource_group.rg.location
  resource_group_name   = azurerm_resource_group.rg.name
  workspace_resource_id = azurerm_log_analytics_workspace.log_ws.id
  workspace_name        = azurerm_log_analytics_workspace.log_ws.name

  plan {
    publisher = "Microsoft"
    product   = "OMSGallery/VMInsights"
  }
}

#Create the VNet
resource "azurerm_virtual_network" "vnet" {
  name                = "vnet-usecase5"
  address_space       = ["10.1.0.0/16"]
  location            = "${azurerm_resource_group.rg.location}"
  resource_group_name = "${azurerm_resource_group.rg.name}"
}

#Create the subnet that hold the web-servers
resource "azurerm_subnet" "subnet_web" {
  name                 = "subnet-web"
  resource_group_name  = "${azurerm_resource_group.rg.name}"
  virtual_network_name = "${azurerm_virtual_network.vnet.name}"
  address_prefixes     = ["10.1.1.0/24"]
}

#Create the subnet that holds the Bastion
resource "azurerm_subnet" "subnet_bastion" {
  name                 = "AzureBastionSubnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.1.2.0/24"]
}

# Create outbound public IP for the NAT Gateway
resource "azurerm_public_ip" "pip_nat" {
  name                = "publicIpForNAT"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
  availability_zone   = "No-Zone"
}

resource "azurerm_nat_gateway" "nat_gw" {
  name                    = "natgw"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku_name                = "Standard"
  idle_timeout_in_minutes = 10

  depends_on              = [azurerm_public_ip.pip_nat]
}

resource "azurerm_subnet_nat_gateway_association" "subnet_4_nat" {
  subnet_id      = azurerm_subnet.subnet_web.id
  nat_gateway_id = azurerm_nat_gateway.nat_gw.id
}

resource "azurerm_nat_gateway_public_ip_association" "pip_4_nat" {
  nat_gateway_id       = azurerm_nat_gateway.nat_gw.id
  public_ip_address_id = azurerm_public_ip.pip_nat.id
}

/*
# Create the PIP for the bastion
resource "azurerm_public_ip" "pip_bastion" {
  name                = "publicIPForBastion"
  location            = "${azurerm_resource_group.rg.location}"
  resource_group_name = "${azurerm_resource_group.rg.name}"
  allocation_method   = "Static"
  sku                 = "Standard"
}

# Create the bastion service in the bastion subnet
resource "azurerm_bastion_host" "bastion" {
  name                = "bastion"
  location            = "${azurerm_resource_group.rg.location}"
  resource_group_name = "${azurerm_resource_group.rg.name}"

  ip_configuration {
    name                 = "IPConfiguration"
    subnet_id            = azurerm_subnet.subnet_bastion.id
    public_ip_address_id = azurerm_public_ip.pip_bastion.id
  }
}
*/

# Create the PIP for the loadbalancer
resource "azurerm_public_ip" "pip_lb" {
  name                = "publicIPForLB"
  location            = "${azurerm_resource_group.rg.location}"
  resource_group_name = "${azurerm_resource_group.rg.name}"
  allocation_method   = "Static"
  sku                 = "Standard"
}

# Create the the loadbalancer and assign it the IP from the previous step
resource "azurerm_lb" "lb" {
  name                = "loadBalancer"
  location            = "${azurerm_resource_group.rg.location}"
  resource_group_name = "${azurerm_resource_group.rg.name}"
  sku                 = "Standard"

  frontend_ip_configuration {
    name                 = "PublicIPAddress"
    public_ip_address_id = azurerm_public_ip.pip_lb.id
  }
}

#Create the backend pool for the LB that will hold the private IPs of the webservers 
resource "azurerm_lb_backend_address_pool" "backendAddressPool" {
  loadbalancer_id     = azurerm_lb.lb.id
  name                = "BackEndAddressPool"
}

# Create a Load Balancer health probe
resource "azurerm_lb_probe" "lbprobes" {
  count               = length(var.ports)
  name                = "probe-port-${var.ports[count.index]}"
  resource_group_name = "${azurerm_resource_group.rg.name}"
  loadbalancer_id     = "${azurerm_lb.lb.id}"
  port                = "${var.ports[count.index]}"
}

resource "azurerm_lb_rule" "lb_rules" {
  count                          = length(var.ports)  
  resource_group_name            = "${azurerm_resource_group.rg.name}"
  loadbalancer_id                = azurerm_lb.lb.id
  name                           = "lbrule-${var.ports[count.index]}"
  protocol                       = "Tcp"
  frontend_port                  = "${var.ports[count.index]}"
  backend_port                   = "${var.ports[count.index]}"
  frontend_ip_configuration_name = "PublicIPAddress"
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.backendAddressPool.id]
  probe_id                       = azurerm_lb_probe.lbprobes[count.index].id
}

resource "azurerm_network_security_group" "nsg_web" {
  name                = "nsg-webserver"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  security_rule {
    name                       = "allow_ssh_sg"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "allow_http_sg"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

#Create 2 FrontEnd NICs for the webservers in the web subnet
resource "azurerm_network_interface" "nic_webservers" {
  count               = 2
  name                = "webnic-${count.index}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "IPConfiguration"
    subnet_id                     = azurerm_subnet.subnet_web.id
    private_ip_address_allocation = "Dynamic"
  }
}

# Associate the NSG with the Web Server NIC
resource "azurerm_network_interface_security_group_association" "association" {
  count                     = 2
  network_interface_id      = "${element(azurerm_network_interface.nic_webservers.*.id, count.index)}"
  network_security_group_id = azurerm_network_security_group.nsg_web.id
}

resource "azurerm_network_interface_backend_address_pool_association" "nic_2_backend" {
  count                   = 2  
  network_interface_id    = "${element(azurerm_network_interface.nic_webservers.*.id,count.index)}"
  ip_configuration_name   = "IPConfiguration"
  backend_address_pool_id = azurerm_lb_backend_address_pool.backendAddressPool.id
}

#Create an availability set with two fault/update domains, so each webserver is placed into its own domain
resource "azurerm_availability_set" "avset" {
  name                          = "avset"
  location                      = "${azurerm_resource_group.rg.location}"
  resource_group_name           = "${azurerm_resource_group.rg.name}"
  platform_fault_domain_count   = 2
  platform_update_domain_count  = 2
  managed                       = true
}

resource "azurerm_virtual_machine" "web_servers" {
  count                 = 2
  name                  = "webserver-${count.index}"
  location              = "${azurerm_resource_group.rg.location}"
  availability_set_id   = azurerm_availability_set.avset.id
  resource_group_name   = "${azurerm_resource_group.rg.name}"
  network_interface_ids = ["${element(azurerm_network_interface.nic_webservers.*.id, count.index)}"]
  vm_size               = "Standard_DS1_v2"

  # Delete the OS disk automatically when deleting the VM
  delete_os_disk_on_termination = true

  storage_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "18.04-LTS"
    version   = "latest"
  }

  storage_os_disk {
    name              = "myosdisk-${count.index}"
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Standard_LRS"
  }

  os_profile {
    computer_name  = "webserver-${count.index}"
    admin_username = "kyndryl"
    admin_password = "Password1234!"
    custom_data    = base64encode(data.template_file.nginx_vm_cloud_init.rendered)
  }

  os_profile_linux_config {
    disable_password_authentication = false
  }

  identity {
    type = "SystemAssigned"
  }

  tags = {
    environment = "terraform-demo"
  }

}

resource "azurerm_virtual_machine_extension" "vm_ext_web" {
  count                      = 2
  name                       = "OmsAgentForLinux"
  virtual_machine_id         = azurerm_virtual_machine.web_servers[count.index].id
  publisher                  = "Microsoft.EnterpriseCloud.Monitoring"
  type                       = "OmsAgentForLinux"
  type_handler_version       = "1.12"
  auto_upgrade_minor_version = true

  settings = <<SETTINGS
    {
        "workspaceId": "${azurerm_log_analytics_workspace.log_ws.workspace_id}"
    }
  SETTINGS

  protected_settings = <<PROTECTEDSETTINGS
    {
        "workspaceKey": "${azurerm_log_analytics_workspace.log_ws.primary_shared_key}"
    }
  PROTECTEDSETTINGS
}

resource "azurerm_virtual_machine_extension" "da_web" {
  count                      = 2
  name                       = "DAExtension"
  virtual_machine_id         = azurerm_virtual_machine.web_servers[count.index].id
  publisher                  = "Microsoft.Azure.Monitoring.DependencyAgent"
  type                       = "DependencyAgentLinux"
  type_handler_version       = "9.5"
  auto_upgrade_minor_version = true
}