## Why

Maintainers can build the Debian package locally, but there is no automated release path that publishes a verified `.deb` artifact for tagged versions. A tag-triggered GitHub Release workflow will make releases repeatable while keeping Debian packaging metadata under `debian/` as the source of truth.

## What Changes

- Add a GitHub Actions workflow that runs only when a version tag matching `v*` is pushed.
- Build the Debian binary package with the existing canonical `dpkg-buildpackage -us -uc -b` path.
- Require the pushed tag version to match `debian/changelog` before publishing artifacts.
- Run package inspection and strict `lintian` validation before release upload.
- Automatically create the corresponding GitHub Release when validation succeeds.
- Upload `.deb`, `.changes`, and `.buildinfo` artifacts to the GitHub Release.
- Explicitly do not publish an apt repository, package index, or apt repository metadata.

## Capabilities

### New Capabilities
- `github-release-deb-publishing`: GitHub Release publication behavior for tag-triggered Debian package builds.

### Modified Capabilities
- `debian-package-build-workflow`: Extend the maintainer workflow requirements from local package building and inspection to include tag-triggered GitHub Release publication.

## Impact

- Adds a GitHub Actions workflow under `.github/workflows/`.
- Uses existing Debian packaging metadata and build tooling; no alternate package assembler is introduced.
- Requires the workflow token permission needed to create or update GitHub Releases and upload release assets.
- Release publishing becomes coupled to `debian/changelog` version discipline for `v*` tags.
