## Context

`sing-gateway` already defines Debian packaging metadata and a canonical maintainer build path based on `dpkg-buildpackage -us -uc -b`. Local documentation explains how to build, inspect, and validate generated `.deb`, `.changes`, and `.buildinfo` artifacts, but the repository does not yet have a GitHub Actions workflow for publishing release assets.

The release workflow should preserve the existing Debian packaging model: metadata remains sourced from `debian/`, the `Makefile` stays a thin helper, and CI uses standard Debian tooling rather than assembling package contents independently.

## Goals / Non-Goals

**Goals:**
- Publish Debian package artifacts automatically when a maintainer pushes a version tag matching `v*`.
- Fail before publishing if the tag version and `debian/changelog` version differ.
- Build with `dpkg-buildpackage -us -uc -b` from the repository root.
- Run strict package validation, including `lintian`, before creating or updating the GitHub Release.
- Upload `.deb`, `.changes`, and `.buildinfo` artifacts to the corresponding GitHub Release.

**Non-Goals:**
- Publishing an apt repository, `Packages` index, `Release` file, or repository signing metadata.
- Signing `.deb`, `.changes`, or apt repository metadata.
- Replacing Debian tooling with `fpm`, `nfpm`, custom `dpkg-deb --build` scripts, or GitHub-specific package assembly.
- Running package lifecycle installation tests as part of the tag release workflow.

## Decisions

### Decision 1: Trigger only on `v*` tag pushes

The workflow will use a tag-only trigger such as `push.tags: ['v*']`. This keeps release publication intentional and avoids creating GitHub Releases from branch pushes or pull requests.

Alternative considered: run on every push and upload workflow artifacts. That is useful for CI validation, but it does not match the desired release-only publication flow.

### Decision 2: Enforce tag/changelog version consistency before build upload

The workflow will derive the release version from `${GITHUB_REF_NAME#v}` and compare it with `dpkg-parsechangelog --show-field Version`. A mismatch fails the job before release asset publication.

This prevents publishing artifacts where the Git tag says one version while the Debian package metadata produces another.

Alternative considered: trust the changelog version and ignore the tag. That makes releases easier to trigger accidentally with misleading asset names and release pages.

### Decision 3: Use standard Debian build tooling unchanged

The workflow will install Debian build and inspection tools on the runner and invoke `dpkg-buildpackage -us -uc -b`. Generated artifacts are expected in the parent directory, matching local maintainer documentation.

Alternative considered: using a custom packaging action or package builder. That would add another source of truth for files, dependencies, and metadata.

### Decision 4: Treat `lintian` as a strict release gate

`lintian` failure will fail the workflow and prevent release publication. Package inspection commands such as `dpkg-deb --info` and `dpkg-deb --contents` should also run before upload to leave useful logs for maintainers.

Alternative considered: advisory lintian output with `continue-on-error`. That is friendlier during early packaging work but does not provide the requested strict release gate.

### Decision 5: Create or update GitHub Release and upload all Debian artifacts

After validation succeeds, the workflow will create the corresponding GitHub Release if needed and upload `.deb`, `.changes`, and `.buildinfo` files. The implementation may use a release action or `gh release` commands, but it must rely on GitHub Release assets rather than apt repository publication.

Alternative considered: uploading only the `.deb`. Including `.changes` and `.buildinfo` preserves build metadata and aligns with the documented Debian artifact set.

## Risks / Trade-offs

- **Runner lintian version drift** → Use the runner-provided lintian initially and keep failures visible; if false positives appear, address packaging metadata rather than weakening the release gate by default.
- **GitHub token permission issues** → Declare the minimal required workflow permissions for release contents so asset upload can succeed.
- **Existing release asset collisions** → Prefer an upload path that can update or replace assets for the same tag, or document that maintainers must delete conflicting assets before rerunning.
- **Dependency availability differences on `ubuntu-latest`** → Keep the build dependency list explicit and use standard Debian tooling; if Ubuntu runner behavior becomes problematic, switch the job to an appropriate Debian container in a future change.
- **Tag format ambiguity** → Scope the first workflow to `v*` tags and compare the stripped `v` value exactly against `debian/changelog`.

## Migration Plan

1. Add the tag-triggered GitHub Actions workflow.
2. Push a test version tag from a branch prepared for release.
3. Confirm the workflow creates a GitHub Release and attaches `.deb`, `.changes`, and `.buildinfo` assets.
4. If release publication fails after the GitHub Release is created, rerun the workflow after correcting the failure or clean conflicting assets manually.

Rollback is deleting or disabling the workflow file; no runtime migration is required.

## Open Questions

- Should release notes be generated automatically by GitHub, left empty, or manually edited after the release is created?
- Should future non-release CI also build the package for pull requests without creating releases?
