# Customization Workflow

This document defines the current operating rule for this fork:

**Do not add new features right now.**

The priority is to get the existing Nimbalyst feature set working correctly, keep the fork close to upstream, and avoid piling new behavior on top of unstable ground.

## Current Goal

Work through existing broken or unreliable behavior before talking about feature expansion.

That means:

- fix regressions
- fix flaky or confusing current behavior
- repair existing workflows that are already supposed to work
- upstream narrow bug fixes when they are clearly valid
- avoid introducing new product surface unless it is strictly required to unblock a repair

This is a stability-first phase, not a feature phase.

## Why This Makes Sense

Adding new features while core behavior is still unreliable usually creates three problems at once:

- it hides whether a bug came from upstream or from our customization layer
- it increases merge pressure with upstream
- it makes validation harder because the app is changing in too many dimensions at once

The better sequence is:

1. stabilize what already exists
2. reduce drift from upstream
3. make the current workflows dependable
4. only then discuss new customization surface

## Scope for This Phase

Allowed work:

- bug fixes in existing features
- cleanup of broken integrations
- reliability fixes
- UI/UX repairs for existing flows
- missing validation around existing behavior
- test coverage for existing bug-prone paths
- small refactors only when they directly support a bug fix

Not allowed for now:


If an idea is valuable but not required to fix an existing problem, defer it.

## Working Definition of "Existing Feature"

An existing feature is anything already present in upstream or already present in this fork that users can reach today.

Examples:

- session wakeups
- queued prompts
- AI session flows
- worktrees
- sync behavior
- editor interactions
- tracker behavior
- settings flows
- extension loading that already exists

If the feature is already in the app but behaves incorrectly, it is in scope.
If it does not exist yet, it is out of scope for this phase.

## Decision Rule Before Making a Change

Before writing code, ask:

1. Is this fixing something that already exists?
2. Can I describe the current broken behavior in one or two plain sentences?
3. Can I name the expected existing behavior?
4. Can I validate the fix without inventing new product surface?
- net-new features
- new workflow concepts
- new extension ideas
- speculative architecture work
- broad customization work that changes product direction
- “while we are here” expansion

If the answer to `1` is no, stop. It is probably feature work.

## Fork Strategy

Keep the repo close to upstream while we are in this bug-fix phase.

- `upstream` = `https://github.com/Nimbalyst/nimbalyst.git`
- `origin` = your fork
- `custom/main` = your working integration branch

Rules:

- sync from upstream regularly
- keep fixes narrow
- upstream clean bug fixes when possible
- do not keep long-lived speculative branches
- do not mix bug repair with unrelated customization

## Branch Strategy

Use short-lived repair branches from `custom/main`.

Suggested naming:

- `fix/<short-name>`
- `bug/<short-name>`

Examples:

- `fix/session-wakeup-timezone`
- `bug/queued-prompts-claim-race`

Do not accumulate multiple unrelated repairs in one branch.

## Daily Flow

### 1. Sync your base

```bash
git checkout custom/main
git fetch upstream --prune
git merge --ff-only upstream/main
git push origin custom/main
```

### 2. Start one repair branch

```bash
git checkout -b fix/<short-name> custom/main
```

### 3. Fix one problem only

A good repair branch has:

- one bug
- one root cause
- one validation story

### 4. Validate

Use the smallest relevant validation:

- targeted unit tests
- targeted E2E coverage
- manual reproduction before and after
- log evidence when needed

### 5. Upstream if appropriate

If the fix is clearly an upstream bug and the patch is clean, open:

- an upstream issue if needed
- an upstream PR if the fix is ready

Do not wait on upstream to continue your own work. Treat upstreaming as parallel cleanup, not a blocker.

## What to Upstream

Good upstream candidates:

- clear bug fixes
- correctness fixes
- timezone/data handling fixes
- race-condition fixes
- validation improvements
- narrowly scoped tests for existing behavior

Bad upstream candidates during this phase:

- personal workflow preferences
- custom authorship rules
- local operating notes
- product-direction experiments
- fork-specific customization ideas

Keep project-shared files in sync with upstream unless the change truly belongs to the shared project.

## How to Write Repair Work

When documenting or discussing a fix, use this structure:

1. What is broken
2. What should happen
3. Root cause
4. Minimal fix
5. Validation

This keeps repair work grounded and prevents feature creep.

## Issue Discipline

When a bug is real and upstream-worthy:

- open the issue with a concrete reproduction
- explain the root cause if known
- include the suggested fix if you have it

Bring a patch when possible. Do not bring only a complaint.

## What We Should Do Next

Maintain a rolling bug-repair list, not a feature list.

For each candidate item:

1. Name the existing feature
2. Describe the broken behavior
3. Define expected behavior
4. Reproduce it
5. Fix it narrowly
6. Validate it
7. Upstream it when the patch is clearly shareable

## Exit Condition for This Phase

We should not return to feature planning until most of the following are true:

- the main existing workflows behave reliably
- current bugs are triaged and shrinking, not growing
- upstream sync is routine instead of painful
- we can validate changes without guesswork
- the fork is no longer carrying avoidable breakage

Until then, keep the work boring, narrow, and correct.
