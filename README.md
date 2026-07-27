# Enclave macOS Image Templates

Enclave-owned Packer templates for building managed Tart images used by secure,
interactive coding-agent sandboxes.

This repository is forked from
[`cirruslabs/macos-image-templates`](https://github.com/cirruslabs/macos-image-templates)
at commit `cd2d1c66981fb28e17fbe908709f1008b25c462a`. The upstream MIT
license is retained. See [UPSTREAM.md](UPSTREAM.md) and [NOTICE.md](NOTICE.md)
for provenance and the Enclave change boundary.

## Image chain

```text
Apple IPSW
  -> ghcr.io/enclave-run/macos-<version>-vanilla@sha256:...
  -> ghcr.io/enclave-run/macos-<version>-base@sha256:...
  -> ghcr.io/enclave-run/macos-<version>-xcode:<xcode-version>@sha256:...
```

No production layer may use a `ghcr.io/cirruslabs/...` image as a parent.
Builds preserve SIP and AMFI, contain no CI runner registration, and do not
install the FSL Tart guest agent. Enclave guest binaries are supplied as pinned
build inputs and installed by the base template.

## Build

Prerequisites on a dedicated Apple Silicon builder:

- Tart 2.34.0 (internal evaluation only until the production license gate is
  satisfied);
- Packer with the Tart plugin;
- enough local disk for vanilla, base, and Xcode layers;
- an Xcode `.xip` already downloaded to `~/XcodesCache`.

Build the full Tahoe chain:

```bash
packer init templates/vanilla-tahoe.pkr.hcl
packer build templates/vanilla-tahoe.pkr.hcl

tart clone tahoe-vanilla tahoe-base
packer init templates/base.pkr.hcl
packer build \
  -var vm_name=tahoe-base \
  -var sbxd_darwin_path=/absolute/path/to/sbxd-darwin \
  -var guest_bootstrap_path=/absolute/path/to/enclave-guest-bootstrap \
  templates/base.pkr.hcl

packer init templates/xcode.pkr.hcl
packer build \
  -var base_image=tahoe-base \
  -var macos_version=tahoe \
  -var 'xcode_version=["26.6"]' \
  -var expected_runtimes_file=data/expected.tahoe.runtimes.txt \
  templates/xcode.pkr.hcl
```

The release workflow pushes only Enclave-owned repositories and records the
source commit, tool versions, image manifest, acceptance results, and digest.
Alias promotion happens in Enclave’s image catalogue after per-node
activation—not inside this repository.

## Security invariants

- SIP and AMFI remain enabled.
- No Apple ID, Fastlane session, reusable token, SSH build key, or CI
  registration survives the build.
- The development user auto-logs in because Xcode, Simulator, Accessibility,
  and LaunchAgent behavior require a GUI session.
- Customer code runs through `sbxd-darwin`; the root bootstrap helper has a
  fixed boot/disk responsibility and never executes customer commands.
- Simulator, Keychain, clipboard, shell history, downloads, and temporary
  provisioning state are normalized before publishing.
- Every release runs `enclave/acceptance/image-acceptance.sh`.
