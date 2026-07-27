packer {
  required_plugins {
    tart = {
      version = "= 1.21.0"
      source  = "github.com/cirruslabs/tart"
    }
  }
}

variable "vm_name" {
  type = string
}

variable "builder_password" {
  type      = string
  sensitive = true
}

variable "sbxd_darwin_path" {
  type        = string
  default     = ""
  description = "Absolute path to the pinned sbxd-darwin binary. Empty is allowed for template validation only."
}

variable "sbxd_darwin_sha256" {
  type        = string
  default     = ""
  description = "Required SHA-256 of sbxd_darwin_path when supplied."

  validation {
    condition = (
      var.sbxd_darwin_sha256 == ""
      || can(regex("^[a-f0-9]{64}$", var.sbxd_darwin_sha256))
    )
    error_message = "sbxd-darwin SHA-256 must be empty or a lowercase SHA-256."
  }
}

variable "guest_bootstrap_path" {
  type        = string
  default     = ""
  description = "Absolute path to the pinned root bootstrap helper. Empty is allowed for template validation only."
}

variable "guest_bootstrap_sha256" {
  type        = string
  default     = ""
  description = "Required SHA-256 of guest_bootstrap_path when supplied."

  validation {
    condition = (
      var.guest_bootstrap_sha256 == ""
      || can(regex("^[a-f0-9]{64}$", var.guest_bootstrap_sha256))
    )
    error_message = "guest bootstrap SHA-256 must be empty or a lowercase SHA-256."
  }
}

source "tart-cli" "tart" {
  vm_name      = "${var.vm_name}"
  cpu_count    = 4
  memory_gb    = 8
  disk_size_gb = 50
  ssh_password = var.builder_password
  ssh_username = "admin"
  ssh_timeout  = "120s"
}

build {
  sources = ["source.tart-cli.tart"]

  provisioner "file" {
    source      = "data/limit.maxfiles.plist"
    destination = "~/limit.maxfiles.plist"
  }

  provisioner "shell" {
    inline = [
      "echo 'Configuring maxfiles...'",
      "sudo mv ~/limit.maxfiles.plist /Library/LaunchDaemons/limit.maxfiles.plist",
      "sudo chown root:wheel /Library/LaunchDaemons/limit.maxfiles.plist",
      "sudo chmod 0644 /Library/LaunchDaemons/limit.maxfiles.plist",
      "echo 'Disabling spotlight...'",
      "sudo mdutil -a -i off",
    ]
  }

  # Create a symlink for bash compatibility
  provisioner "shell" {
    inline = [
      "touch ~/.zprofile",
      "ln -s ~/.zprofile ~/.profile",
    ]
  }

  provisioner "shell" {
    inline = [
      "/bin/bash -c \"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\"",
      "echo \"export LANG=en_US.UTF-8\" >> ~/.zprofile",
      "echo 'eval \"$(/opt/homebrew/bin/brew shellenv)\"' >> ~/.zprofile",
      "echo \"export HOMEBREW_NO_AUTO_UPDATE=1\" >> ~/.zprofile",
      "echo \"export HOMEBREW_NO_INSTALL_CLEANUP=1\" >> ~/.zprofile",
    ]
  }

  provisioner "shell" {
    inline = [
      "source ~/.zprofile",
      "brew --version",
      "brew update",
      "brew install wget unzip zip ca-certificates cmake gcc git-lfs jq yq gh",
      "brew install equinix-labs/otel-cli/otel-cli",
      "brew install curl || true", // doesn't work on Monterey
      "brew install --cask git-credential-manager",
      "git lfs install",
      "sudo softwareupdate --install-rosetta --agree-to-license"
    ]
  }

  // Add GitHub to known hosts
  // Similar to https://github.com/actions/runner-images/blob/main/images/macos/scripts/build/configure-ssh.sh
  provisioner "shell" {
    inline = [
      "mkdir -p ~/.ssh"
    ]
  }
  provisioner "file" {
    source      = "data/github_known_hosts"
    destination = "~/.ssh/known_hosts"
  }

  provisioner "shell" {
    inline = [
      "source ~/.zprofile",
      "brew install libyaml", # https://github.com/rbenv/ruby-build/discussions/2118
      "brew install rbenv",
      "echo 'if which rbenv > /dev/null; then eval \"$(rbenv init -)\"; fi' >> ~/.zprofile",
      "brew install mise",
      "source ~/.zprofile",
      "rbenv install 2.7.8", // latest 2.x.x before EOL
      "rbenv install -l | grep -v - | tail -2 | xargs -L1 rbenv install",
      "rbenv global $(rbenv install -l | grep -v - | tail -1)",
      "gem install bundler",
    ]
  }
  provisioner "shell" {
    inline = [
      "source ~/.zprofile",
      "brew install node@24",
      "echo 'export PATH=\"/opt/homebrew/opt/node@24/bin:$PATH\"' >> ~/.zprofile",
      "source ~/.zprofile",
      "node --version",
      "npm install --global yarn",
      "yarn --version",
    ]
  }
  provisioner "shell" {
    inline = [
      "sudo safaridriver --enable",
    ]
  }
  provisioner "shell" {
    inline = [
      "source ~/.zprofile",
      "brew install awscli"
    ]
  }

  # Enable UI automation, see https://github.com/cirruslabs/macos-image-templates/issues/136
  provisioner "shell" {
    script = "scripts/automationmodetool.expect"
    environment_vars = [
      "BUILDER_PASSWORD=${var.builder_password}",
    ]
  }

  // some other health checks
  provisioner "shell" {
    inline = [
      "source ~/.zprofile",
      "test -d /Users/admin",
      "test -f ~/.ssh/known_hosts"
    ]
  }

  dynamic "provisioner" {
    for_each = var.sbxd_darwin_path != "" ? [1] : []
    labels   = ["file"]
    content {
      source      = var.sbxd_darwin_path
      destination = "/tmp/enclave-upload-sbxd-darwin"
    }
  }

  dynamic "provisioner" {
    for_each = var.guest_bootstrap_path != "" ? [1] : []
    labels   = ["file"]
    content {
      source      = var.guest_bootstrap_path
      destination = "/tmp/enclave-upload-guest-bootstrap"
    }
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
      "INSTALL_SBXD=${var.sbxd_darwin_path != "" ? "1" : "0"}",
      "INSTALL_BOOTSTRAP=${var.guest_bootstrap_path != "" ? "1" : "0"}",
      "SBXD_SHA256=${var.sbxd_darwin_sha256}",
      "GUEST_BOOTSTRAP_SHA256=${var.guest_bootstrap_sha256}",
    ]
  }
}
