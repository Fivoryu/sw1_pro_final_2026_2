---
name: university-repositories
description: "Trigger: university repository, course project, GitHub repo creation, monorepo, submodule. Create verified repositories without inferring names or wiring."
license: Apache-2.0
metadata:
  author: "gentleman-programming"
  version: "1.0"
---

## Activation Contract

Load only for creating or naming GitHub repositories for university subjects/projects. If course context or required naming facts are unclear, stop and ask what repository name the user intends; never infer a course, abbreviation, classification, or unrelated repository.

## Hard Rules

- Normalize only user-supplied or confirmed components: subject abbreviation, academic year, semester, course-defined project type/classification (for example `final`, `parcial`, `proyecto1`), and, only for product submodules, surface. Use lowercase snake_case; never invent missing components.
- A general project monorepo has no surface. A submodule is a separate repository and includes its normalized surface. Preserve the RoomForge order shown here; these are conventions, not universal names: `sw1_pro_final_2026_2`, `sw1_pro_final_backend_2026_2`, and `sw1_pro_final_frontend_2026_2`.
- Default to create-only. Creating a submodule must not edit `.gitmodules`, local paths, commits, or pushes; connect it to a monorepo only after an explicit request.
- Use local `gh` authentication/keyring; never request or expose tokens or private keys. Verify owner, visibility, exact candidate name, and organization creation policy.

## Decision Gates

| Condition | Action |
| --- | --- |
| Missing or ambiguous facts | Ask the intended repository name and stop. |
| Monorepo | Omit surface. |
| Product submodule | Include surface; keep it separate unless connection is explicit. |
| Existing candidate | Do not create; report and ask how to proceed. |
| Organization owner | Verify repository-creation policy before authorization. |

## Execution Steps

1. Collect and confirm all name components, repository kind, owner, and visibility; show the exact candidate.
2. Run `gh auth status`; verify the owner/policy and check existence with `gh repo view OWNER/NAME`.
3. Require explicit authorization, then run `gh repo create OWNER/NAME --public|--private`.
4. Verify with `gh repo view OWNER/NAME` and report URL, exact name, owner, visibility, relationship, and every unperformed connection, local edit, commit, or push.

## Output Contract

Return status, confirmed components and candidate, preflight/authentication result, creation result, verification result, and explicit unperformed steps. Never claim wiring, commits, or pushes that were not requested and verified.

## References

- `../../AGENTS.md`
