## 1. Release Workflow

- [x] 1.1 Create `.github/workflows/` if it does not already exist.
- [x] 1.2 Add a GitHub Actions workflow that triggers only on pushed tags matching `v*`.
- [x] 1.3 Configure minimal workflow permissions required to create or update GitHub Releases and upload release assets.
- [x] 1.4 Install Debian build and inspection tools in the workflow runner.

## 2. Build and Validation

- [x] 2.1 Add a workflow step that compares `${GITHUB_REF_NAME#v}` with `dpkg-parsechangelog --show-field Version` and fails on mismatch before publishing.
- [x] 2.2 Add a workflow step that builds the package with `dpkg-buildpackage -us -uc -b` from the repository root.
- [x] 2.3 Add package inspection steps for `dpkg-deb --info` and `dpkg-deb --contents` on the generated `.deb` artifact.
- [x] 2.4 Add strict `lintian` validation for generated `.changes` and `.deb` artifacts, with failures blocking release publication.

## 3. GitHub Release Publication

- [x] 3.1 Add a release publication step that creates the GitHub Release for the tag if needed after validation succeeds.
- [x] 3.2 Upload generated `.deb`, `.changes`, and `.buildinfo` files as GitHub Release assets.
- [x] 3.3 Ensure the workflow does not generate or publish apt repository metadata or package indexes.

## 4. Documentation and Verification

- [x] 4.1 Update maintainer documentation to describe the `v*` tag-triggered GitHub Release publication flow.
- [x] 4.2 Document the tag/changelog version consistency requirement and uploaded release artifacts.
- [x] 4.3 Verify OpenSpec status for this change and ensure the workflow YAML is syntactically valid.
