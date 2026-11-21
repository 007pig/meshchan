# Phase 1E.8 CI and retention validation

## Accepted source and image

The repository base was the PR #46 merge,
`b00807de20cddede3122aa8cfd71b352d0ffbb08`. GitHub reported PR head
`e2d5432171f83b1a9c3e43284bacb1be1e5ba8f6`. The accepted image is the
675,911,154-byte `Meshchan-0.1.0-rc.1-build8-macos-arm64-local.dmg`
from `local-dmg-008`, based on recipe 55 and product source
`a29430b608658a8b56d619f641dc8600346b6d27`. Its SHA-256 is
`b42021e054e65e47893d84437100a6b9e51a2ea93eb7a060c12e70fdb4a6ca28`.
See the [selected 1E.7 acceptance](phase-1e7-dmg.md#current-reviewed-candidate-and-image)
and the [retention procedure](../releases/phase-1e8-ci-retention.md).

## Historical GitHub records

The authenticated GitHub API queries ran from 15:04:34 to 15:04:42 UTC on
November 21, 2026. The retained
snapshots include the original run, attempt and paginated job and artifact
responses, exact workflow, and attempt-specific log ZIP. All were attempt 1
and completed successfully in both jobs. GitHub listed zero artifacts for
each run.

| Run | Event | Checkout | `check` | `macos-app` |
| --- | --- | --- | --- | --- |
| [44747988036](https://github.com/007pig/meshchan/actions/runs/44747988036) | Push | `a29430b608658a8b56d619f641dc8600346b6d27` | 136328165539 | 136328164805 |
| [44915147891](https://github.com/007pig/meshchan/actions/runs/44915147891) | Push | `e2d5432171f83b1a9c3e43284bacb1be1e5ba8f6` | 136879051561 | 136879051359 |
| [44915191801](https://github.com/007pig/meshchan/actions/runs/44915191801) | Pull request | `b3f698918ccf4f5031bb6357f9378c98696d601a` | 136879183662 | 136879183406 |

The PR run tested its merge checkout, whose second parent was the PR head.
The historical workflow has its own bytes for each checkout. All three runs
used Ubuntu 26.04.1 x86_64 and macOS 15.8.2 (24H232) arm64 and reported Flutter
3.50.0 and Dart 3.14.0. The macOS logs report Xcode 16.4, SDK 15.5 and Apple
Clang 17.0.0. In the product run, the Ubuntu runner logged Python 3.14.4 in
a probe. The frozen macOS Python version and historical Linux compiler
versions were not retained. The Step 7 runs reported CPython 3.15.2 on both
jobs.

| Snapshot | Manifest SHA-256 | Workflow SHA-256 |
| --- | --- | --- |
| Product source | `0682d0c89ac4e752df8611232ec5abfd595048b2f2150f1c52c3139baa7f3659` | `eeef7fe89a6bd97c446cde9f816082ab2f50045253154ab2eaf9905942fbf6a4` |
| Step 7 push | `7b3c4980d8f7f15a9ace62ba068c0dbbc0065c333f1d093e7fff45efa7d7923d` | `a0b5a7c8c8fa48a8b063719bd1be3e52c3e966c75113ccbf5da331d3faf8a591` |
| Step 7 PR merge | `9ca289a6aa0e6fd25c35d4bf01cc4cf1df4647b900da8afd26c4483ddb4135d1` | `a0b5a7c8c8fa48a8b063719bd1be3e52c3e966c75113ccbf5da331d3faf8a591` |
