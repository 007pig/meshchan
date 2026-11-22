# Meshchan 0.1.0-rc.1 Build 10 engineering release

This Build 10 candidate is held. Both retained images contain a local
`snapshot.aot` path in the packaged CLI and a macOS temporary-directory prefix
in `docs/development.md` inside the first-party source archive. The staged
review manifest records the earlier audit. The shipped library replacement tool
also rejects signed inputs carrying download quarantine. Publication requires
closing these findings and qualifying the replacement image.

Build 10 pairs Meshchan for macOS arm64 with the complete `meshctl`
command-line bundle. App identity is `0.1.0-rc.1+10`, CLI identity is
`0.1.0-rc.1`, and the Apple bundle uses short version `0.1.0` and build
`10`. The frozen source is `be88abba92c47e3814e5bca4b8cc1e8c1efd6ad7`.
The `release-manifest.json` file in the attachment set identifies
the actual image, download byte count, SHA-256, and acceptance scope.
[Compiled source](https://github.com/007pig/meshchan/commit/be88abba92c47e3814e5bca4b8cc1e8c1efd6ad7)

Both products carry local ad hoc signatures. The read-only disk image
container is unsigned and unnotarized. See the
[engineering guide](rc1-build10-engineering-guide.md) for checksum
verification, complete installation, macOS item approval, USB use, ownership,
normal Quit, and backup. See the
[source materials guide](rc1-build10-source-materials.md) for the project
license, exact source distributions and user library replacement.

## What changed

- The Release App build removes local debug paths. The CLI builds from a
  stable Dart package URI. The original build-path check covered all App and
  CLI Mach-O files and missed the CLI temporary snapshot path.
- The image contains signed products and complete corresponding source
  and license materials with public inventory records. Raw build and
  synthetic test records are retained independently.
- This source includes the later RC1 USB initialization changes from
  PR #49. It supports offline drafts, profiles, settings and diagnostic
  History, plus explicit finite operations on a selected USB Companion.
  The source-only OpenHop peer remains an engineering acceptance tool.
  [USB compatibility change](https://github.com/007pig/meshchan/pull/49)

## Acceptance and publication

The staged attachment manifest records the earlier acceptance results for this
exact candidate. The [validation summary](rc1-build10-validation-summary.md)
explains their scope and the open privacy findings. Build 9 hardware records
and Build 8 Safari installation and Beta upgrade records apply to their
respective images. The successful Build 10 CI run used the same source commit
shown above.
[Build 10 software evidence](https://github.com/007pig/meshchan/actions/runs/45014763866)

GitHub Releases is the intended distribution channel. The replacement needs
its own completed gates and attachment manifest before publication, followed
by verification of the actual downloads. [Meshchan Releases](https://github.com/007pig/meshchan/releases)
