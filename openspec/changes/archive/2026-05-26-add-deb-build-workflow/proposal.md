## Why

The repository now contains Debian packaging metadata, but maintainers do not yet have a complete, repeatable process for producing and validating a `.deb` artifact from a clean checkout. Documenting and automating the build path reduces release mistakes around missing Debian metadata, package contents, inert-install guarantees, and maintainer-script behavior.

## What Changes

- Add a documented Debian package build workflow for `sing-gateway` covering prerequisites, metadata requirements, build commands, artifact locations, and validation commands.
- Add explicit requirements for the repository to be buildable with standard Debian tooling once packaging metadata is complete.
- Add verification guidance for inspecting package metadata, installed files, lintian output, install/remove/purge lifecycle behavior, and the package's inert installation contract.
- Add optional convenience automation for maintainers, such as a local build script or Make target, if it preserves the same standard Debian build path.

## Capabilities

### New Capabilities
- `debian-package-build-workflow`: Defines the maintainer-facing workflow for building and validating the `sing-gateway` Debian package artifact.

### Modified Capabilities
- `sing-gateway-debian-package`: Clarifies that the package metadata required by Debian tooling must be complete enough to build the binary package with standard Debian tools.

## Impact

- Affected files are expected to include Debian metadata under `debian/`, maintainer documentation such as `README.md` or `docs/sing-gateway.md`, and possibly non-invasive convenience automation.
- No runtime behavior or command-line API changes are intended.
- No package install-time activation behavior should change; the package must remain inert until `sing-gateway enable` is run explicitly.
