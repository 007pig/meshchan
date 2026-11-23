# Meshchan 0.1.0-rc.1 Build 10 engineering candidate

The macOS arm64 engineering image pairs Meshchan App `0.1.0-rc.1+10` with
the complete `meshctl 0.1.0-rc.1` bundle from `c5cd5021da5e62c60127678b650d970721263296`.
The 669,400,332-byte image has SHA-256
`0f7232479e33cdfb28862b2253bfdd92aad623f985e4fbe9a89989cab949e4bb`. Publication is blocked.

Both products use local ad hoc signatures. The read-only disk image
container is unsigned and unnotarized. The matching
[engineering guide](rc1-build10-engineering-guide.md) covers download
checks, installation, normal macOS approvals, and the data directory.

Recipe 57 changes the CLI AOT snapshot to omit its host temporary path.
The corresponding-source archive removes the identified host temporary
path entries. Creation and independent image extraction audits reported
zero findings. The shipped public native replacement tool can prepare
separate signed copies while preserving ordinary download quarantine.

The App supports offline drafts, profiles, settings, and History.
USB diagnostics use an explicitly selected MeshCore Companion. See the
[validation summary](rc1-build10-validation-summary.md) for this image's
acceptance scope and remaining gates. The [source and license index](rc1-build10-source-materials.md)
maps the corresponding source and replacement materials.

The exact image was downloaded with Safari and installed together in a
fresh independent host-only macOS VM. The test verified Safari quarantine,
separate App, CLI and SQLite approvals, offline Save, storage ownership,
normal Quit, and reopen.

The maintainer used the shipped rebuild and signing code to prepare native
libraries and ran the replacement App and CLI from same-guest copies of the
Safari installation. Both loaded their synthetic libraries under normal
macOS protections. The CLI returned an empty port list, and the App showed
empty ports after Refresh and quit normally. The end-to-end invocation
of the shipped preparation command was measured on the separate engineering
extraction.
