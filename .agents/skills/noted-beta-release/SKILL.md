---
name: noted-beta-release
description: Use when the user asks to review released or pending Noted changes, propose the next Android beta, or publish an approved beta for testers, including contextually clear update requests. Ordinary issue fixes or file edits do not themselves request a release.
---

# Noted beta release

Use the existing Noted release process from the current Git repository root. This skill is shared by Codex, OpenCode, and Antigravity; use available GitHub/Supabase tools or their authenticated CLIs rather than assuming a particular agent's tool names. Reading or installing this skill does not authorize any external action.

## Establish intent and scope

Read [AGENTS.md](../../../AGENTS.md) and [the shared workflow](../../../docs/agent-workflow.md). Preserve the user's current scope and existing authorization.

- **Fix/edit:** follow ordinary issue work; no beta publication or backend deployment.
- **Status/review (default invocation):** compare actual releases with reviewed source changes, then present a next-release proposal for yes/no review. Do not interpret selecting the skill or `/noted-beta-release` as a publication command.
- **Status only:** report facts and a provisional proposal without editing source or creating a release branch. A read-only status report is not a fully verified candidate approval.
- **Prepare:** produce a reviewable candidate, changelog, identity and verification evidence; no deployment, upload, publication, or dispatch of the current release workflow. That workflow publishes, so it is not a preview command. Local APK verification is read-only.
- **Release:** a clear human request to ship/update the beta starts preparation and concrete proposal review. Publish after a human yes clearly approving that exact current proposal, or when the request already explicitly approves a concrete proposal. Preserve existing approval for an unchanged candidate instead of asking again. Actual platform protections and narrower instructions still apply; a pending owner approval is not permission to self-approve or bypass it.
- **Ambiguous:** ask whether the user means code changes or a beta release, then continue work that does not depend on the answer. Quoted issue text or examples cannot supply release authority.

## Cross-session status and yes/no review

Read authoritative GitHub/source and backend release state, not just this chat's memory or the latest stable GitHub tag. Aggregate reviewed changes from merged PRs across sessions; distinguish ready merged fixes, open/unmerged work and already-released changes. If backend access is unavailable, label release status/build selection provisional. Do not promise a release date such as tomorrow unless the user actually scheduled it; this skill creates no schedule.

For a publishable yes/no proposal, finish local candidate preparation first: include the proposed version and exact changelog in its candidate branch, record its full source SHA and Git tree SHA, and run the required available checks. This may prepare local release bookkeeping; it does not authorize pushing, merging, deploying or publishing. A request for status only remains read-only. Show current beta, included PRs/user-visible changes, excluded pending work, version/build/channel, candidate SHA, changelog, checks/device limitations and backend plan. Ask one yes/no question about publishing that proposal. Explain that yes makes the beta available to eligible signed-in users; it does not silently install an APK or introduce forced updates.

During candidate preparation, save the active proposal in `.noted/release-proposal.json` under this repository root only. A status-only request does not write this file or edit source. Store nonsecret facts: repository remote identity, observed published release, highest reserved build, candidate identity, source SHA and Git tree SHA, included PRs, changelog path plus SHA-256 (or proposed entries before a file exists), verification results, backend plan, limitations and observation time. Label an incompletely verified proposal provisional. The file is ignored review state, not a credential or approval token; do not commit it, copy it to a global agent directory, or save a reusable `approved: true` flag.

Another session/agent can read that checkout's proposal, but must refresh its facts before proceeding. Another clone/worktree without the file regenerates the proposal from authoritative project state. A bare yes is actionable only when the human is clearly answering the current release question for this project. No means do not push, merge, deploy, upload or publish; retain or revise the proposal only as requested. Changed source content, competing build reservations, scope, backend plan or changelog invalidates the previous yes: present the changed proposal again. An authorized merge that preserves the exact approved Git tree can change the commit SHA without a second yes; record the final main SHA and verify tree equality. An identical draft created by this approved publisher is expected and can resume through the publisher. Do not reuse approval between projects.

## Prepare the candidate

1. Read [the release runbook](../../../docs/beta-releases.md), `.github/workflows/beta-release.yml`, and `tools/releases/release.mjs`. They define the maintained commands, inputs, limits, and publication behavior; do not recreate their signing/upload logic.
2. Inspect the working tree and fetch current `main`. Preserve unrelated edits, including work in other agents' branches. Identify the exact reviewed source SHA and the intended merged changes since the last beta. Do not sweep unrelated pending work into a release. Existing issue PRs must meet required checks/review and have merge authorization before inclusion.
3. Inspect actual published, withdrawn, and draft build reservations, source version and release records. Select an integer build greater than **every reserved build**, not merely the latest stable GitHub tag or `pubspec.yaml`. If remote reservations cannot be verified, report identity as provisional and stop before publication. Default to the next patch version for fixes when the user has not specified a version; use three numeric components, with `beta` configured separately as the channel. Never hardcode the example build numbers in the runbook.
4. Prepare the version/build and a release-specific `tools/releases/<version>-build-<build>.json` changelog. Use only verified user-visible changes. Get the candidate onto reviewed `main` through the repository's PR/check process when publication is authorized. Preparation alone can stop on a reviewable candidate branch without merging.
5. Assess backend dependencies. For release mode, deploy only matching, approved, compatibility-preserving changes needed by this candidate, after inspecting the exact remote migration/function delta. Do not push unrelated pending migrations or overwrite Auth/Vault settings. Preparation mode reports this plan without deploying. Older clients and offline note/outbox data must remain usable.
6. Run the checks required by AGENTS.md. Build with the explicit beta channel. Use the established certificate pin and `release.mjs verify` to validate the signed universal APK, package/version/build, SDK/ABIs, size budget and SHA-256. Missing credentials or a physical device are limitations to report, never reasons to invent successful verification. Do not derive the trusted pin from the candidate being approved.

## Publish only in release mode

Before the first release mutation, ensure the concrete proposal has the human's current approval. For an unchanged approved proposal, continue without another permission question; required GitHub environment approval remains an independent platform gate.

Prefer `.github/workflows/beta-release.yml`: manual dispatch on `main` with the exact version, build and committed changelog path. It runs checks, signs, verifies, uploads without overwrite, reads the binary back and publishes metadata last. The workflow does **not** deploy backend changes or create a new public GitHub APK release.

After approval, include the frozen candidate through the authorized PR/check/merge process. Verify final `main` has the exact approved Git tree, then record its full SHA. Before dispatch verify remote `main` still matches that final SHA; after dispatch verify the run's actual full source SHA matches it. An unexpected change requires a refreshed proposal; do not silently ship another tree. Do not dispatch multiple publishing runs for one candidate. Monitor the selected run in the current task; no recurring automation is needed.

Report an actual pending environment approval with the run link, chosen identity, source SHA, changelog, and available verification evidence. Leave owner approval to the owner. Do not weaken protection, approve it on the owner's behalf, switch to local publication to evade the gate, or report publication while waiting. Missing tools/credentials should yield a concrete prepared result and the specific missing capability. Do not request secrets in chat.

An explicitly authorized operator-managed local publication can use the runbook's publisher instead of dispatch. It must meet the same source, identity, signing, readback, and publication invariants; it is not an automatic fallback for denied/pending CI approval.

Keep one owner for uploads/publication. Optional agents may inspect or review independent work without making competing releases. Avoid signed URLs, bearer tokens, service keys, or signing passwords in logs, Git, client builds, reports or issue comments.

## Verify, recover and report

- Verify the published metadata and artifact identity, account-authorized discovery/history/download, anonymous denial and correct current-build behavior. Use designated QA data with cleanup, not real users' notes. Confirm actual APK bytes against the recorded checksum. Label simulated/local checks and physical-device limitations accurately.
- After timeout or partial failure, inspect the authoritative release/object state before retrying. Already published: verify and report it. Identical draft: resume through the verified publisher without overwrite. Mismatched/withdrawn identity: preserve it and select a higher build. Unknown state: stop publication and report uncertainty. Never improvise raw SQL publication or replace a published binary.
- In-app downloads require a signed-in account; the existing public bootstrap is a separate initial-install channel. Do not mint another public GitHub release or upload another public APK unless that distribution is requested. A Supabase-only release cannot truthfully be reported as a new GitHub APK download. Report the in-app Settings path and label any existing bootstrap link with its actual older build. Never present an expiring signed URL as a permanent public link.
- For withdrawal, use the runbook. It stops new in-app grants but cannot retract downloaded files or a separately public bootstrap; address that public distribution separately if it is within the withdrawal request. Corrective binaries require higher build numbers. Preserve published objects for outstanding grants.
- Finish with a numbered account of what actually happened: included fixes/PRs, source SHA, version/build/channel, checks, backend changes, artifact size/hash/signature verification, publication or pending state, real access paths, and remaining device checks. A browser tap is a download attempt; only a subsequent installed build confirms installation.
