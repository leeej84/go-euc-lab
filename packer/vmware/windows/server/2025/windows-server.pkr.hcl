  /*
      DESCRIPTION:
      Microsoft Windows Server 2022 template using the Packer Builder for VMware vSphere (vsphere-iso).
  */

  //  BLOCK: packer
  //  The Packer configuration.

  packer {
    required_version = ">= 1.8.0"
    required_plugins {
      vsphere = {
        version = ">= v1.0.3"
        source  = "github.com/hashicorp/vsphere"
      }
    }

    required_plugins {
      windows-update = {
        version = ">= 0.14.0"
        source  = "github.com/rgl/windows-update"
      }
    }

    # required_plugins {
    #   ansible = {
    #     version = ">= 1.0.0"
    #     source  = "github.com/hashicorp/ansible"
    #   }
    # }
  }

  //  BLOCK: locals
  //  Defines the local variables.

  locals {
    build_by        = "Built by: HashiCorp Packer ${packer.version}"
    build_date      = formatdate("YYYY-MM-DD hh:mm ZZZ", timestamp())
    build_version   = formatdate("YYMM", timestamp())
    iso_paths       = ["[] /vmimages/tools-isoimages/${var.vm_guest_os_family}.iso"]
    manifest_date   = formatdate("YYYY-MM-DD hh:mm:ss", timestamp())
    manifest_path   = "${path.cwd}/manifests/"
    manifest_output = "${local.manifest_path}${var.vm_guest_os_family}-${var.vm_guest_os_name}-${var.vm_guest_os_version}-${var.vm_guest_os_edition_standard}.json"
  }

  //  BLOCK: source
  //  Defines the builder configuration blocks.

  source "vsphere-iso" "windows-server" {

    // vCenter Server Endpoint Settings and Credentials
    vcenter_server      = var.vsphere_endpoint
    username            = var.vsphere_username
    password            = var.vsphere_password
    insecure_connection = var.vsphere_insecure_connection

    // vSphere Settings
    datacenter = var.vsphere_datacenter
    cluster    = var.vsphere_cluster
    datastore  = var.vsphere_datastore
    folder     = var.vsphere_folder

    // Virtual Machine Settings
    guest_os_type        = var.vm_guest_os_type
    vm_name              = "${var.vm_guest_os_family}-${var.vm_guest_os_name}-${var.vm_guest_os_version}-${var.vm_guest_os_edition_standard}-v${local.build_version}"
    firmware             = var.vm_firmware
    CPUs                 = var.vm_cpu_sockets
    cpu_cores            = var.vm_cpu_cores
    CPU_hot_plug         = var.vm_cpu_hot_add
    RAM                  = var.vm_mem_size
    RAM_hot_plug         = var.vm_mem_hot_add
    cdrom_type           = var.vm_cdrom_type
    disk_controller_type = var.vm_disk_controller_type
    storage {
      disk_size             = var.vm_disk_size
      disk_controller_index = 0
      disk_thin_provisioned = var.vm_disk_thin_provisioned
    }
    network_adapters {
      network      = var.vsphere_network
      network_card = var.vm_network_card
    }
    vm_version           = var.common_vm_version
    remove_cdrom         = var.common_remove_cdrom
    tools_upgrade_policy = var.common_tools_upgrade_policy

    // Removable Media Settings
    iso_url      = "${var.iso_path}/${var.iso_file}"
    iso_paths    = local.iso_paths

    cd_files = [
      "${path.cwd}/packer/vmware/scripts/${var.vm_guest_os_family}/"
    ]
    cd_content = {
      "autounattend.xml" = templatefile("data/autounattend.pkrtpl.hcl", {
        build_username       = var.build_username
        build_password       = var.build_password
        build_organization   = var.build_organization
        vm_inst_os_language  = var.vm_inst_os_language
        vm_inst_os_keyboard  = var.vm_inst_os_keyboard
        vm_inst_os_image     = var.vm_inst_os_image_standard_desktop
        vm_inst_os_kms_key   = var.vm_inst_os_kms_key_standard
        vm_guest_os_language = var.vm_guest_os_language
        vm_guest_os_keyboard = var.vm_guest_os_keyboard
        vm_guest_os_timezone = var.vm_guest_os_timezone
        network_address      = cidrhost(var.network_cidr, var.network_address)
        network_subnet       = cidrnetmask(var.network_cidr)
        network_gateway      = cidrhost(var.network_cidr, var.network_gateway)
        network_dns          = cidrhost(var.network_cidr, var.network_dns)
      })
    }

    // Boot and Provisioning Settings
    http_port_min    = var.common_http_port_min
    http_port_max    = var.common_http_port_max
    boot_order       = var.vm_boot_order
    boot_wait        = var.vm_boot_wait
    boot_command     = var.vm_boot_command
    ip_wait_timeout  = var.common_ip_wait_timeout
    shutdown_command = var.vm_shutdown_command
    shutdown_timeout = var.common_shutdown_timeout

    // Communicator Settings and Credentials
    communicator   = "winrm"
    winrm_username = var.build_username
    winrm_password = var.build_password
    winrm_port     = var.communicator_port
    winrm_timeout  = var.communicator_timeout

    // Template and Content Library Settings
    convert_to_template = var.common_template_conversion
    dynamic "content_library_destination" {
      for_each = var.common_content_library_name != null ? [1] : []
      content {
        library     = var.common_content_library_name
        description = "Version: v${local.build_version}\nBuilt on: ${local.build_date}\n${local.build_by}"
        ovf         = var.common_content_library_ovf
        destroy     = var.common_content_library_destroy
        skip_import = var.common_content_library_skip_export
      }
    }
  }

  //  BLOCK: build
  //  Defines the builders to run, provisioners, and post-processors.

  build {
    sources = ["source.vsphere-iso.windows-server"]

    provisioner "powershell" {
      environment_vars = [
        "BUILD_USERNAME=${var.build_username}"
      ]
      elevated_user     = var.build_username
      elevated_password = var.build_password
      scripts           = formatlist("${path.cwd}/%s", var.scripts)
    }

    provisioner "powershell" {
      elevated_user     = var.build_username
      elevated_password = var.build_password
      inline            = var.inline
    }

    provisioner "windows-update" {
      pause_before    = "30s"
      search_criteria = "IsInstalled=0"
      filters = [
        "exclude:$_.Title -like '*VMware*'",
        "exclude:$_.Title -like '*Preview*'",
        "exclude:$_.Title -like '*Defender*'",
        "exclude:$_.InstallationBehavior.CanRequestUserInput",
        "include:$true"
      ]
      restart_timeout = "120m"
    }

    post-processor "manifest" {
      output     = local.manifest_output
      strip_path = true
      strip_time = true
      custom_data = {
        build_username           = var.build_username
        build_date               = local.build_date
        build_version            = local.build_version
        common_data_source       = var.common_data_source
        common_vm_version        = var.common_vm_version
        vm_cpu_cores             = var.vm_cpu_cores
        vm_cpu_count             = var.vm_cpu_sockets
        vm_disk_size             = var.vm_disk_size
        vm_disk_thin_provisioned = var.vm_disk_thin_provisioned
        vm_firmware              = var.vm_firmware
        vm_guest_os_type         = var.vm_guest_os_type
        vm_mem_size              = var.vm_mem_size
        vm_network_card          = var.vm_network_card
        vsphere_cluster          = var.vsphere_cluster
        vsphere_datacenter       = var.vsphere_datacenter
        vsphere_datastore        = var.vsphere_datastore
        vsphere_endpoint         = var.vsphere_endpoint
        vsphere_folder           = var.vsphere_folder
      }
    }
  }
