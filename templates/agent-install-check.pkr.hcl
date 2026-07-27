# Non-release qualification harness. It proves that the final guest-agent
# refresh replaces a stale base layer with the exact pinned artifacts. Delete
# its `enclave-agent-install-check` VM after the check.
packer {
  required_plugins {
    tart = {
      version = "= 1.21.0"
      source  = "github.com/cirruslabs/tart"
    }
  }
}

variable "builder_password" {
  type      = string
  sensitive = true
}

variable "sbxd_darwin_path" {
  type = string
}

variable "sbxd_darwin_sha256" {
  type = string
}

variable "guest_bootstrap_path" {
  type = string
}

variable "guest_bootstrap_sha256" {
  type = string
}

source "tart-cli" "agent_install_check" {
  vm_base_name = "tahoe-base"
  vm_name      = "enclave-agent-install-check"
  cpu_count    = 4
  memory_gb    = 8
  disk_size_gb = 50
  headless     = true
  ssh_password = var.builder_password
  ssh_username = "admin"
  ssh_timeout  = "120s"
}

build {
  sources = ["source.tart-cli.agent_install_check"]

  provisioner "file" {
    source      = var.sbxd_darwin_path
    destination = "/tmp/enclave-upload-sbxd-darwin"
  }

  provisioner "file" {
    source      = var.guest_bootstrap_path
    destination = "/tmp/enclave-upload-guest-bootstrap"
  }

  provisioner "file" {
    source      = "data/com.enclave.sbxd-darwin.plist"
    destination = "/tmp/com.enclave.sbxd-darwin.plist"
  }

  provisioner "file" {
    source      = "data/com.enclave.guest-bootstrap.plist"
    destination = "/tmp/com.enclave.guest-bootstrap.plist"
  }

  provisioner "shell" {
    script = "scripts/install-enclave-agents.sh"
    environment_vars = [
      "INSTALL_SBXD=1",
      "INSTALL_BOOTSTRAP=1",
      "SBXD_SHA256=${var.sbxd_darwin_sha256}",
      "GUEST_BOOTSTRAP_SHA256=${var.guest_bootstrap_sha256}",
    ]
  }

  provisioner "shell" {
    inline = [
      "test \"$(shasum -a 256 /usr/local/libexec/enclave/sbxd-darwin | awk '{print $1}')\" = '${var.sbxd_darwin_sha256}'",
      "test \"$(shasum -a 256 /usr/local/libexec/enclave/enclave-guest-bootstrap | awk '{print $1}')\" = '${var.guest_bootstrap_sha256}'",
    ]
  }
}
