# Contributing to Meshchan

Meshchan welcomes focused improvements to its macOS app, CLI, shared Dart
packages, tests, and documentation. The community edition is licensed under
**GPL-3.0-only**. The project may also offer **paid, closed-source commercial
editions** under separate licenses.

## Contribution rights and acceptance

Before your original copyrightable contribution is merged, read and explicitly
accept [CLA.md](CLA.md), version **1.0** (`meshchan-cla-1.0`). You retain your
copyright. The CLA separately permits **007pig** to use your contribution in the
GPL community edition and proprietary commercial editions and to grant the
corresponding sublicenses. It is not merely permission to charge for a GPL copy.

Acceptance applies to the identified contribution, not automatically to your
past work or unrelated future submissions. You may decline the CLA and continue
to exercise your GPL rights to use, modify, fork, and redistribute the community
edition; upstream merge requires the additional contribution permission.
Bug reports, questions, and feature requests without copyrightable submissions
do not require a CLA. 007pig's own original work does not require a separate
contributor agreement with 007pig.

For each pull request:

1. Verify that you own the relevant rights or can accept for the named owner.
   Obtain any required employer/client/coauthor authorization first.
2. Identify every third-party file or copied fragment, its source, license,
   notices, and any exclusion from your grant. Third-party code is reviewed
   separately; a CLA cannot remove its restrictions.
3. Follow [CLA section 9](CLA.md#9-how-to-accept) and post the complete acceptance
   template yourself from your authenticated GitHub account. Reference an
   immutable commit containing CLA version 1.0 and the exact document hash.
4. Cover the pull request's actual head commit. After pushing new commits, post
   a new complete acceptance comment. Each rights holder must be covered; one
   author's comment does not authorize the work of other authors.

A checkbox or `Signed-off-by` alone is insufficient. Agreement changes require
new acceptance; maintainers do not infer acceptance from submitting a PR.
Do not publish private identity documents, home addresses, employer agreements,
passwords, or signing secrets. Resolve confidential authority evidence with
007pig through a mutually agreed private process before merge.

To calculate the hash of the exact agreement stored at a selected commit on
macOS, replace the example token with its full commit SHA:

```sh
git show FULL_COMMIT_SHA:CLA.md | shasum -a 256
```

On Linux, `sha256sum` can replace `shasum -a 256`. Use the same commit in the
acceptance URL. A signed Git commit can help establish provenance, but it does
not replace explicit acceptance of the CLA terms.

## Working in this repository

Read [AGENTS.md](AGENTS.md) and the [developer guide](docs/development.md) before
running tools or tests. The workspace contains:

- `apps/meshchan_app`: Flutter macOS app.
- `apps/meshctl`: Dart CLI.
- `packages/meshchan_core`: shared application/storage behavior.
- `packages/meshcore_link`: protocol and transport behavior.

Use the existing Flutter SDK and bundled Dart. Start from locked resolution;
do not upgrade dependencies or the SDK for an unrelated change. Use `python3`,
with the verified local interpreter/version required by AGENTS.md. Follow the
developer guide for generation, formatting, analysis, and relevant tests.

Keep changes focused and describe the concrete resulting behavior. Preserve
product identity, version/build rules, storage compatibility, and protocol
contracts unless the pull request intentionally changes and validates them.
Use American English for project documentation, comments, and tool output.

Run checks appropriate to your change and report exact commands and outcomes,
including failures and unavailable environments. A documentation-only change
does not require hardware or a complete product rebuild. Use owned synthetic
fixtures for storage/process tests, never a user's production database.

Hardware-free macOS GUI work follows the [VM guide](docs/macos-vm-gui-testing.md)
and the applicable repository skill. Real USB/serial or RF validation needs its
own explicit authorization and follows the hardware policy; opening a pull
request or accepting this CLA does not grant hardware-test permission.

## Pull request contents and maintainer review

Include the problem, final change, relevant validation, and material limitations.
Link the acceptance comments and disclose third-party material. Use the pull
request template to help review; its checkbox does not execute the CLA.

Before merge, the maintainer must verify and retain the acceptance evidence
listed in CLA section 9, covering every relevant rights holder and the head
being merged. Record the source head and merge/squash commit relationship. Stop
the merge when authority, exclusions, or acceptance is unresolved. This is a
manual requirement; no automatic CLA approval is claimed.
007pig or an expressly authorized representative must post the Recipient's
acknowledgement described in CLA section 9 before merge. This records acceptance
of the Contributor's grant and the Recipient's commitments.

## License and distribution boundaries

[LICENSE](LICENSE) contains the unchanged GNU GPLv3 text;
[COPYRIGHT](COPYRIGHT) applies GPL-3.0-only to Meshchan's first-party work and
records the project attribution. The CLA supplies separate incoming permissions
to 007pig. It does not amend the community GPL, withdraw existing GPL grants,
transfer contributor copyright, or override third-party terms.

For release work, follow the [1E.3 materials contract](docs/releases/phase-1e3-licenses.md).
New contributions or policy files change source/material inputs and require
fresh material binding. Publishing this CLA does not prove that past
contributors signed it, that every existing contribution is cleared for
proprietary use, or that the open GPL engine/runtime source gate is closed.
