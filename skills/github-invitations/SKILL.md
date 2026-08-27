---
name: github-invitations
description: "Trigger: GitHub invitation, repository collaborator, add collaborator, grant repo access. Safely invite exact GitHub logins to authorized repositories."
license: Apache-2.0
metadata:
  author: "gentleman-programming"
  version: "1.0"
---

## Activation Contract

Load for GitHub repository collaborator invitations, access grants, permission changes, or access-state audits. Treat organization membership invitations as a separate workflow.

## Hard Rules

- Use the locally authenticated `gh`/keyring. Never request or expose tokens, passwords, or SSH private keys.
- Require the exact GitHub login; never infer it from an email. If only an email is supplied, ask for the login.
- Verify authentication, targets, user existence, and effective/pending state before mutation. Never silently choose Admin.
- Preserve human control: no invitation, permission change, cancellation, or mutation retry without explicit authorization; read-only idempotent rechecks are allowed.

## Decision Gates

| Condition | Action |
| --- | --- |
| RoomForge project scope | Enumerate exactly: monorepo, backend, frontend/panel, captura mobile, cliente mobile. Ask if scope or permission is missing. |
| Missing login or access level | Stop and ask; map UI `Write` to REST `permission=push`. |
| Organization membership request | Use the separate organization flow requiring owner/member-management authority; never infer it from repository Admin. |

## Execution Steps

1. Run `gh auth status`; derive and confirm exact owner/repository targets and requested permission.
2. Verify `users/{login}` exists. For every target, inspect the collaborator and repository pending-invitation state; avoid duplicates or unintended elevation.
3. After explicit authorization, perform one direct `PUT` per target through `gh api`, using `repos/{owner}/{repo}/collaborators/{login}` and the requested permission (for Write: `-f permission=push`). Record each HTTP outcome.
4. Re-query pending invitations and effective collaborator state. Classify every target as accepted, pending, failed, or untouched; an invitation success is not acceptance.

## Output Contract

Return the confirmed targets, permission, preflight state, per-target HTTP outcomes, post-mutation classification, untouched targets, and blockers. Distinguish pending from accepted and do not claim unverified access.

## References

- `../../AGENTS.md`
