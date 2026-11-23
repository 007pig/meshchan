# Phase 1E.12 engineering publication

The selected macOS arm64 image is
`Meshchan-0.1.0-rc.1-build10-macos-arm64-local.dmg` (669,400,332 bytes,
SHA-256 `0f7232479e33cdfb28862b2253bfdd92aad623f985e4fbe9a89989cab949e4bb`).
It contains Meshchan App `0.1.0-rc.1+10` and the complete `meshctl 0.1.0-rc.1`
from `c5cd5021da5e62c60127678b650d970721263296`. Both products carry local
ad hoc signatures. The read-only image is unsigned and unnotarized.

The four candidate-specific gates passed, and the nine approved attachments
were published as the engineering prerelease on November 23, 2026. The
`v0.1.0-rc.1` tag resolves to the full frozen commit above. The release is
excluded from Latest. [Build 10 on GitHub Releases](https://github.com/007pig/meshchan/releases/tag/v0.1.0-rc.1)

All nine anonymous downloads and the downloaded-product offline runtime
checks passed. [1E.12 validation record](../validation/phase-1e12-publication.md#public-release-and-anonymous-download)

The original nine proposed attachments and their verification procedure
remain recorded in the [1E.11 handoff](phase-1e11-release-materials.md#build-10-replacement-candidate).

## Publish the accepted candidate

Use the restored candidate to verify the final attachment set. Keep the DMG,
original `SHA256SUMS`, and in-image materials unchanged. Bind the seven leaf
assets in `release-manifest.json`, then bind the leaf assets and manifest in
`RELEASE-SHA256SUMS`. Save the final manifest and checksum pins, upload list,
and release body digest in a private durable record.

The release title is **Meshchan 0.1.0-rc.1 Build 10 engineering release**.
Use the GitHub prerelease channel in `007pig/meshchan`, with Latest disabled.
Resolve `refs/tags/v0.1.0-rc.1` to the full compiled source before creating
or editing a prerelease. For an annotated tag, follow the tag object to its
commit. Before writing, check the remote tag and list releases with a
GitHub account that has push access. Follow pagination and match `tag_name`
exactly. The public Release page and the published-release lookup can miss
an existing draft. [GitHub release listing](https://docs.github.com/en/rest/releases/releases#list-releases)

Stop on a conflicting tag, release, or asset. If both the tag and release
are absent, create the tag at the approved compiled commit and independently
confirm the remote ref before proceeding. If the matching release is
already public, confirm its release ID, prerelease status, body, and
attachment metadata against the retained record, then continue directly
to anonymous download verification. Resume a matching draft after verifying
its ID, body, and existing assets.

Create a draft with explicit tag verification only when the matching tag
exists and there is no release for it. Upload approved missing files by
name. After an interrupted transfer, fetch the draft and asset states
again. Keep `uploaded` assets that match the approved names and sizes,
and check their digests when GitHub provides them. Retry only missing
names. A GitHub `502` can leave an empty asset in `starter` state. A
maintainer can remove only the confirmed zero-byte placeholder for that
failed upload from the matching draft, then fetch the assets again and
resume when the name is absent. Stop on other unexpected asset states or
mismatched files.
[GitHub upload behavior](https://docs.github.com/en/rest/releases/assets#upload-a-release-asset)

Download the draft assets and compare their actual bytes with the independent
pins. Verify the tag, draft ID, body, and complete asset set again before
publishing the same draft. GitHub's generated source archives are separate
from the nine uploaded files.

## Verify the public download

Download the nine named attachments from the Release body's **Downloads**
section anonymously into a fresh directory. Keep GitHub's generated
**Source code (zip)** and **Source code (tar.gz)** archives outside that
directory. [Build 10 on GitHub Releases](https://github.com/007pig/meshchan/releases/tag/v0.1.0-rc.1)

Check the public body links, release and asset IDs, peeled tag, file sizes,
individual SHA-256 values, and both checksum lists. Use the final public
manifest and outer checksum pins with the attachment checker.
[Final public pins](../validation/phase-1e12-publication.md#public-release-and-anonymous-download) ·
[Attachment checker](phase-1e11-release-materials.md#stage-and-verify-the-release-attachments)

Verify and mount the downloaded image read-only, then check the complete
product, signature, and material inventories. Eject the owned image normally.

Use products from the public download for the isolated offline CLI check
and VM App launch, Save, Quit, and reopen. Reuse prior Safari quarantine
evidence for the same bytes and record the actual public download method.
Append the observed release and download results to the validation record
and private archive. Preserve the published asset bytes.
