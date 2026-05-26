## Context

`sing-gateway` already has Debian packaging files for an inert companion package: `debian/control`, `debian/install`, `debian/rules`, conffile metadata, and maintainer scripts. The package behavior is specified, but the maintainer workflow for actually building and validating a `.deb` artifact is not yet captured end-to-end.

The immediate gap is release readiness rather than runtime behavior. A complete workflow needs to make the standard Debian path obvious, identify required metadata, and define validation steps that protect the package's core contract: installing the package must place files only and must not activate gateway integration or mutate host network state.

## Goals / Non-Goals

**Goals:**
- Make `dpkg-buildpackage`/`debuild` the canonical local build path.
- Ensure the repository contains the Debian metadata needed by standard tooling, including changelog and copyright information.
- Document where build artifacts are emitted and how maintainers inspect package control data and installed file layout.
- Define validation checks for package contents, lintian output, install inertness, explicit enable behavior, remove behavior, and purge cleanup.
- Allow convenience automation only as a thin wrapper around the canonical Debian tooling.

**Non-Goals:**
- Replacing Debian tooling with a custom packaging system such as `fpm` or `nfpm`.
- Publishing to an APT repository or signing release artifacts.
- Changing `sing-gateway` runtime behavior, systemd integration semantics, or install-time inertness.
- Adding CI, containerized build infrastructure, or cross-distribution packaging unless a later change scopes it explicitly.

## Decisions

### Use standard Debian tooling as the source of truth

The workflow will be based on `dpkg-buildpackage -us -uc -b` and may mention `debuild -us -uc -b` as an equivalent convenience command. This keeps the build compatible with Debian conventions and avoids introducing an alternate package assembler that could diverge from `debian/` metadata.

Alternative considered: use a custom `dpkg-deb --build` script. That is simpler for quick local experiments but bypasses normal Debian helper behavior, changelog handling, substvars, and lintian expectations.

### Keep convenience automation optional and transparent

If a helper such as a `make deb` target or shell script is added, it should call the same canonical Debian build command and should not encode separate file lists or package metadata. Documentation should remain useful even without the helper.

Alternative considered: make the helper the only supported path. That would hide important Debian mechanics and make troubleshooting harder.

### Validate behavior at package boundaries

The workflow should check the package artifact rather than only source files. Required validation should include package metadata inspection, package contents inspection, lintian review, local install, inertness checks, explicit enable flow, remove, and purge. These steps directly map to the existing package contract.

Alternative considered: rely only on the existing shell test suite. Source-level tests are useful, but they do not prove the built `.deb` contains the intended files or that maintainer scripts behave correctly through dpkg lifecycle operations.

## Risks / Trade-offs

- **Risk: local build succeeds while clean-environment build fails** → Document the required build packages and leave room for later CI or containerized builds.
- **Risk: lintian emits warnings that are not immediately actionable** → Treat lintian as required review output, not necessarily a zero-warning gate unless the project later chooses that policy.
- **Risk: install tests mutate a developer machine** → Prefer disposable Debian/Ubuntu containers or VMs for full install/remove/purge lifecycle validation.
- **Risk: convenience automation drifts from Debian metadata** → Keep any helper as a thin wrapper over `dpkg-buildpackage` or `debuild` only.
