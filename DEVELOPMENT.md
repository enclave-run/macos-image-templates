# Development

## Validate without building

The Tart Packer plugin currently publishes Darwin artifacts only, so
`packer init` and `packer validate` must run on an Apple host. Linux can still
run `packer fmt` and the Enclave boundary validator.

```bash
packer fmt -check -recursive templates

for template in templates/vanilla-*.pkr.hcl; do
  packer init "$template"
  packer validate "$template"
done

packer init templates/base.pkr.hcl
packer validate \
  -var vm_name=template-validation-base \
  templates/base.pkr.hcl

packer init templates/xcode.pkr.hcl
packer validate \
  -var base_image=template-validation-base \
  -var macos_version=tahoe \
  -var 'xcode_version=["26.6"]' \
  -var expected_runtimes_file=data/expected.tahoe.runtimes.txt \
  templates/xcode.pkr.hcl
```

`scripts/validate-enclave-boundary.sh` additionally rejects Cirrus image
parents, SIP-disable templates, CI runner payloads, and the upstream Tart guest
agent.

## Updating upstream

1. Fetch `cirruslabs/main`.
2. Review changes against the exact commit in `UPSTREAM.md`.
3. Merge or cherry-pick only the unattended-install, Xcode, Simulator,
   normalization, and validation changes Enclave needs.
4. Re-run the boundary validator and Packer validation.
5. Update `UPSTREAM.md` with the new reviewed commit and notable decisions.

Published upstream images are never used as a fallback.
