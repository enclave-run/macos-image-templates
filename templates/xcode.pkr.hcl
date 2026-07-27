packer {
  required_plugins {
    tart = {
      version = "= 1.21.0"
      source  = "github.com/cirruslabs/tart"
    }
  }
}

variable "macos_version" {
  type = string
}

variable "builder_password" {
  type      = string
  sensitive = true
}

variable "base_image" {
  type        = string
  description = "Enclave-owned local name or immutable OCI digest for the base image."
}

variable "xcode_version" {
  type = list(string)
}

variable "xcode_app_archive" {
  type        = string
  default     = ""
  description = "Optional absolute path to a trusted zip containing Xcode.app. Internal bootstrap alternative to a signed XIP."
}

variable "xcode_app_archive_sha256" {
  type        = string
  default     = ""
  description = "Required SHA-256 of xcode_app_archive when the trusted zip bootstrap is used."

  validation {
    condition = (
      var.xcode_app_archive_sha256 == ""
      || can(regex("^[a-f0-9]{64}$", var.xcode_app_archive_sha256))
    )
    error_message = "Xcode app archive SHA-256 must be empty or a lowercase SHA-256."
  }
}

variable "additional_ios_builds" {
  type    = list(string)
  default = []
}

variable "additional_tvos_builds" {
  type    = list(string)
  default = []
}

variable "xcode_components" {
  type        = list(string)
  default     = []
  description = "Additional Xcode components to download."
}

variable "expected_runtimes_file" {
  type        = string
  default     = ""
  description = "Path to file containing expected simulator runtimes. If empty, runtime verification is skipped."
}

variable "tag" {
  type    = string
  default = ""
}

variable "disk_size" {
  type    = number
  default = 140
}

variable "disk_free_mb" {
  type    = number
  default = 15000
}

variable "sbxd_darwin_path" {
  type        = string
  default     = ""
  description = "Absolute path to the pinned sbxd-darwin binary. When set, the final Xcode layer refreshes the base-installed binary before acceptance."
}

variable "guest_bootstrap_path" {
  type        = string
  default     = ""
  description = "Absolute path to the pinned root bootstrap helper. When set, the final Xcode layer refreshes the base-installed binary before acceptance."
}

source "tart-cli" "tart" {
  vm_base_name = var.base_image
  // use tag or the last element of the xcode_version list
  vm_name      = "${var.macos_version}-xcode:${var.tag != "" ? var.tag : var.xcode_version[0]}"
  cpu_count    = 4
  memory_gb    = 8
  disk_size_gb = var.disk_size
  headless     = true
  ssh_password = var.builder_password
  ssh_username = "admin"
  ssh_timeout  = "120s"
}

locals {
  xcode_install_provisioners = var.xcode_app_archive == "" ? [
    for version in reverse(sort(var.xcode_version)) : {
      type = "shell"
      inline = [
        "source ~/.zprofile",
        "sudo xcodes install ${version} --experimental-unxip --path /Users/admin/Downloads/Xcode_${version}.xip --select --empty-trash",
        // get selected xcode path, strip /Contents/Developer and move to stable locations
        "INSTALLED_PATH=$(xcodes select -p)",
        "CONTENTS_DIR=$(dirname $INSTALLED_PATH)",
        "APP_DIR=$(dirname $CONTENTS_DIR)",
        "sudo mv $APP_DIR /Applications/Xcode_${version}.app",
        "sudo xcode-select -s /Applications/Xcode_${version}.app",
        "xcodebuild -downloadPlatform iOS",
        "xcodebuild -runFirstLaunch",
        "df -h",
      ]
    }
  ] : []
}

build {
  sources = ["source.tart-cli.tart"]

  provisioner "file" {
    source      = "scripts/write-kcpassword.py"
    destination = "/tmp/write-kcpassword.py"
  }

  provisioner "shell" {
    inline = [
      // Tahoe's sysadminctl can report SACSetAutoLoginPassword error 22 for
      // this unattended account. Generate the documented kcpassword format
      // ourselves after Command Line Tools are present, then validate it.
      "printf '%s' '${var.builder_password}' | sudo /usr/bin/python3 /tmp/write-kcpassword.py",
      "sudo defaults write /Library/Preferences/com.apple.loginwindow autoLoginUser admin",
      "sudo chown root:wheel /etc/kcpassword",
      "sudo chmod 0600 /etc/kcpassword",
      "rm /tmp/write-kcpassword.py",
      "test \"$(sudo defaults read /Library/Preferences/com.apple.loginwindow autoLoginUser)\" = admin",
      "test \"$(stat -f '%Su:%Sg:%Lp' /etc/kcpassword)\" = root:wheel:600",
      // Remove the retired in-guest screen/input helper from any transitional
      // parent image. Computer use terminates at the host's VNC capability.
      "sudo rm -f /usr/local/libexec/enclave/enclave-macos-ui",
    ]
  }

  provisioner "shell" {
    inline = [
      // The Tart Packer plugin expands the virtual disk but does not grow the
      // APFS container once the base layer has already removed the recovery
      // partition. Repair the backup GPT onto the expanded virtual disk, then
      // grow APFS explicitly before transferring Xcode or runtimes.
      "printf 'y\\n' | sudo diskutil repairDisk disk0",
      "sudo diskutil apfs resizeContainer disk0s2 0",
      "df -k / | awk 'NR == 2 { exit !($2 > 120 * 1024 * 1024) }'",
    ]
  }

  provisioner "shell" {
    script = "scripts/automationmodetool.expect"
    environment_vars = [
      "BUILDER_PASSWORD=${var.builder_password}",
    ]
  }

  provisioner "shell" {
    inline = [
      "source ~/.zprofile",
      "brew --version",
      "brew update",
      "brew upgrade"
    ]
  }

  provisioner "shell" {
    inline = [
      "source ~/.zprofile",
      "brew install xcodes",
      "xcodes version",
    ]
  }

  dynamic "provisioner" {
    for_each = var.xcode_app_archive == "" ? [1] : []
    labels   = ["file"]
    content {
      sources     = [for version in var.xcode_version : pathexpand("~/XcodesCache/Xcode_${version}.xip")]
      destination = "/Users/admin/Downloads/"
    }
  }

  dynamic "provisioner" {
    for_each = var.xcode_app_archive != "" ? [1] : []
    labels   = ["file"]
    content {
      source      = var.xcode_app_archive
      destination = "/Users/admin/Downloads/Xcode.app.zip"
    }
  }

  provisioner "shell" {
    inline = [
      "source ~/.zprofile",
      "df -h",
    ]
  }

  // iterate over all Xcode versions and install them
  // select the latest one as the default
  dynamic "provisioner" {
    for_each = local.xcode_install_provisioners
    labels   = ["shell"]
    content {
      inline = provisioner.value.inline
    }
  }

  dynamic "provisioner" {
    for_each = var.xcode_app_archive != "" ? [1] : []
    labels   = ["shell"]
    content {
      inline = [
        "source ~/.zprofile",
        "test ${length(var.xcode_version)} -eq 1",
        "printf '%s  %s\\n' '${var.xcode_app_archive_sha256}' /Users/admin/Downloads/Xcode.app.zip | shasum -a 256 -c -",
        "sudo ditto -x -k /Users/admin/Downloads/Xcode.app.zip /Applications",
        "rm /Users/admin/Downloads/Xcode.app.zip",
        "test -d /Applications/Xcode.app",
        "sudo mv /Applications/Xcode.app /Applications/Xcode_${var.xcode_version[0]}.app",
        "codesign --verify --deep --strict --verbose=2 /Applications/Xcode_${var.xcode_version[0]}.app",
        "spctl --assess --type execute --verbose=2 /Applications/Xcode_${var.xcode_version[0]}.app",
        "sudo xcode-select -s /Applications/Xcode_${var.xcode_version[0]}.app/Contents/Developer",
        "sudo xcodebuild -license accept",
        "xcodebuild -runFirstLaunch",
        "xcodebuild -downloadPlatform iOS",
        "df -h",
      ]
    }
  }

  dynamic "provisioner" {
    for_each = length(var.xcode_version) > 2 ? [2] : []
    labels   = ["shell"]
    content {
      inline = [
        "source ~/.zprofile",
        "sudo xcode-select -s /Applications/Xcode_${var.xcode_version[2]}.app/Contents/Developer",
        "xcodebuild -downloadAllPlatforms",
      ]
    }
  }

  dynamic "provisioner" {
    for_each = length(var.xcode_version) > 1 ? [1] : []
    labels   = ["shell"]
    content {
      inline = [
        "source ~/.zprofile",
        "sudo xcode-select -s /Applications/Xcode_${var.xcode_version[1]}.app/Contents/Developer",
        "xcodebuild -downloadAllPlatforms",
      ]
    }
  }

  provisioner "shell" {
    inline = [
      "source ~/.zprofile",
      "sudo xcode-select -s /Applications/Xcode_${var.xcode_version[0]}.app/Contents/Developer",
      "xcodebuild -downloadAllPlatforms",
    ]
  }

  provisioner "shell" {
    inline = concat(
      ["source ~/.zprofile"],
      [
        for runtime in var.additional_ios_builds : "xcodebuild -downloadPlatform iOS -buildVersion ${runtime}"
      ]
    )
  }

  provisioner "shell" {
    inline = concat(
      ["source ~/.zprofile"],
      [
        for runtime in var.additional_tvos_builds : "xcodebuild -downloadPlatform tvOS -buildVersion ${runtime}"
      ]
    )
  }

  provisioner "shell" {
    inline = concat(
      ["source ~/.zprofile"],
      [
        for component in var.xcode_components : "xcodebuild -downloadComponent ${component}"
      ]
    )
  }

  provisioner "shell" {
    inline = [
      "source ~/.zprofile",
      "brew install libimobiledevice ideviceinstaller ios-deploy carthage",
      "brew install xcodegen xcbeautify swiftformat swiftlint swiftgen licenseplist",
      "brew install mint",
      "git clone --depth 1 https://github.com/tuist/homebrew-tuist.git \"$(brew --repository)/Library/Taps/tuist/homebrew-tuist\"",
      "rm -rf \"$(brew --repository)/Library/Taps/tuist/homebrew-tuist/Casks\"",
      "tuist_version=$(ruby -ne 'if $_ =~ %r{/download/([^/]+)/}; puts $1; exit; end' \"$(brew --repository)/Library/Taps/tuist/homebrew-tuist/Aliases/tuist\") && brew trust --formula \"tuist/tuist/tuist@$tuist_version\" && brew install --formula \"tuist/tuist/tuist@$tuist_version\"",
      "rbenv install 3.3.10",
      "rbenv global 3.3.10", # fastlane conflicts with 3.4.0+ https://github.com/fastlane/fastlane/issues/29527
      "gem update",
      "gem install fastlane",
      "gem install cocoapods",
      "gem install xcpretty",
      "gem uninstall --ignore-dependencies ffi && gem install ffi -- --enable-libffi-alloc"
    ]
  }

  // Copy expected runtimes file if provided
  dynamic "provisioner" {
    for_each = var.expected_runtimes_file != "" ? [1] : []
    labels   = ["file"]
    content {
      source      = var.expected_runtimes_file
      destination = "/Users/admin/runtimes.expected.txt"
    }
  }

  // Verify simulator runtimes match expected list if file was provided
  dynamic "provisioner" {
    for_each = var.expected_runtimes_file != "" ? [1] : []
    labels   = ["shell"]
    content {
      inline = [
        "source ~/.zprofile",
        "xcrun simctl list runtimes > /Users/admin/runtimes.actual.txt",
        "diff -q /Users/admin/runtimes.actual.txt /Users/admin/runtimes.expected.txt || (echo 'Simulator runtimes do not match expected list' && cat /Users/admin/runtimes.actual.txt && exit 1)",
        "rm /Users/admin/runtimes.actual.txt /Users/admin/runtimes.expected.txt"
      ]
    }
  }

  # useful utils for mobile development
  provisioner "shell" {
    inline = [
      "source ~/.zprofile",
      "brew install graphicsmagick imagemagick",
      "brew install wix/brew/applesimutils",
      "brew install gnupg"
    ]
  }

  # inspired by https://github.com/actions/runner-images/blob/fb3b6fd69957772c1596848e2daaec69eabca1bb/images/macos/provision/configuration/configure-machine.sh#L33-L61
  provisioner "shell" {
    inline = [
      "source ~/.zprofile",
      "curl -o AppleWWDRCAG3.cer https://www.apple.com/certificateauthority/AppleWWDRCAG3.cer",
      "curl -o DeveloperIDG2CA.cer https://www.apple.com/certificateauthority/DeveloperIDG2CA.cer",
      "curl -o add-certificate.swift https://raw.githubusercontent.com/actions/runner-images/fb3b6fd69957772c1596848e2daaec69eabca1bb/images/macos/provision/configuration/add-certificate.swift",
      "swiftc -suppress-warnings add-certificate.swift",
      "sudo ./add-certificate AppleWWDRCAG3.cer",
      "sudo ./add-certificate DeveloperIDG2CA.cer",
      "rm add-certificate* *.cer"
    ]
  }

  // check there is at least 15GB of free space and fail if not
  provisioner "shell" {
    inline = [
      "source ~/.zprofile",
      "df -h",
      "export FREE_MB=$(df -m | awk '{print $4}' | head -n 2 | tail -n 1)",
      "[[ $FREE_MB -gt ${var.disk_free_mb} ]] && echo OK || exit 1"
    ]
  }

  # Disable apsd[1][2] daemon as it causes high CPU usage after boot
  #
  # [1]: https://iboysoft.com/wiki/apsd-mac.html
  # [2]: https://discussions.apple.com/thread/4459153
  provisioner "shell" {
    inline = [
      "sudo launchctl unload -w /System/Library/LaunchDaemons/com.apple.apsd.plist"
    ]
  }

  # Wait for the "update_dyld_sim_shared_cache" process[1][2] to finish
  # to avoid wasting CPU cycles after boot
  #
  # [1]: https://apple.stackexchange.com/questions/412101/update-dyld-sim-shared-cache-is-taking-up-a-lot-of-memory
  # [2]: https://stackoverflow.com/a/68394101/9316533
  provisioner "shell" {
    inline = [
      "source ~/.zprofile",
      "xcrun simctl runtime dyld_shared_cache update --all || sleep 180",
      "xcrun simctl list -v"
    ]
  }

  # Reinstall the exact release inputs in the final layer. The base image
  # contains these binaries so it can boot independently, but refreshing here
  # prevents a long Xcode bake from publishing stale agent or bootstrap code.
  dynamic "provisioner" {
    for_each = var.sbxd_darwin_path != "" ? [1] : []
    labels   = ["file"]
    content {
      source      = var.sbxd_darwin_path
      destination = "/tmp/sbxd-darwin"
    }
  }

  dynamic "provisioner" {
    for_each = var.guest_bootstrap_path != "" ? [1] : []
    labels   = ["file"]
    content {
      source      = var.guest_bootstrap_path
      destination = "/tmp/enclave-guest-bootstrap"
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
    ]
  }

  provisioner "file" {
    source      = "enclave/acceptance/image-acceptance.sh"
    destination = "/tmp/enclave-image-acceptance.sh"
  }

  provisioner "shell" {
    inline = [
      "sudo install -d -o root -g wheel -m 0700 /var/db/enclave",
      "sudo touch /var/db/enclave/runtime-seal-required",
      "sudo chown root:wheel /var/db/enclave/runtime-seal-required",
      "sudo chmod 0600 /var/db/enclave/runtime-seal-required",
      // The vanilla builder enables stock SSH only so Packer can provision
      // the image. Persistently disable it before acceptance. Do not bootout
      // the currently loaded job: that would sever this final provisioner,
      // while the disabled override still prevents SSH on the next boot.
      "sudo launchctl disable system/com.openssh.sshd",
      "chmod 0755 /tmp/enclave-image-acceptance.sh",
      "/tmp/enclave-image-acceptance.sh",
      "rm /tmp/enclave-image-acceptance.sh",
      "rm -rf ~/Downloads/* ~/.Trash/*",
      "xcrun simctl shutdown all || true",
      "xcrun simctl erase all || true",
      "history -p || true",
      "rm -f ~/.zsh_history ~/.bash_history"
    ]
  }
}
