# Team Workflow

How our team works with this Nimbalyst fork. Companion to [CUSTOMIZATION_WORKFLOW.md](./CUSTOMIZATION_WORKFLOW.md), which covers *what* kind of work to do (philosophy and scope). This doc covers *how* the team operates day to day (mechanics).

If you are joining the team, read this once. Most of it is one-time setup; the daily flow at the end is what you'll actually do.

## The two repos that matter

| Repo | What it's for |
|---|---|
| `git.agiterra.org/tankloop/Nymbalyst` | Our team's repo. The trunk (`main`) is what our packaged dogfood builds are produced from. The team's auto-updater consumes binary releases hosted here. **This is the only repo you need write access to.** |
| `github.com/Nimbalyst/nimbalyst` | Upstream Nimbalyst. The product itself. Read-only for us. We file PRs against it when we need to fix something in the product. |

You will also create a **personal GitHub fork** of upstream Nimbalyst to file PRs from. That fork lives under your own GitHub account and is yours to manage; nobody else needs access to it.

## Day-to-day: just using Nimbalyst

Nothing to do. The packaged Nimbalyst on your machine auto-updates from agiterra's `dogfood-current` rolling release whenever a new build is shipped. You'll see the standard "Update available" prompt; click and relaunch.

If you don't see the **Dogfood** option in `Settings → Advanced → Update Channel`, you're running upstream Nimbalyst, not the team build. See the next section.

## One-time bootstrap onto the team build

If you've never installed the team's Nimbalyst on this machine:

1. **Download the team DMG** from:
   https://git.agiterra.org/tankloop/Nymbalyst/releases/download/dogfood-current/Nimbalyst-macOS-arm64.dmg

2. **Quit your current Nimbalyst** if running, drag the new app from the DMG into `Applications` (replacing any existing copy), and launch.

   Your settings, workspaces, and database carry over. They live in `~/Library/Application Support/@nimbalyst/electron/`, untouched by reinstalling the binary.

3. **Verify**: `Help > About` should show a version with the `-dogfood` suffix (e.g. `0.58.22-dogfood`).

4. **Switch to the dogfood update channel** so future updates pull from our team feed:

   - Go to `Settings → Advanced → Update Channel`
   - Pick `Dogfood (Custom Feed)` from the dropdown
   - In the "Dogfood Feed URL" field that appears, paste:
     ```
     https://git.agiterra.org/tankloop/Nymbalyst/releases/download/dogfood-current/
     ```
     (Trailing slash matters.)
   - Save.

From now on the in-app updater watches our feed instead of upstream's. The next time someone ships a build, your app sees it on its next check.

## Setting up to make code changes

You only need to do this once per machine. Replace `<your-github-username>` with yours.

```bash
# 1. Clone the team repo from agiterra
git clone git@git.agiterra.org:tankloop/Nymbalyst.git nimbalyst
cd nimbalyst

# 2. Add upstream and your personal fork as remotes
git remote add upstream https://github.com/Nimbalyst/nimbalyst.git
git remote add my-github https://github.com/<your-github-username>/nimbalyst.git

# 3. Fetch all
git fetch --all

# 4. Install dependencies
npm install
```

Your remotes now look like this:

| Remote | Points at | What you use it for |
|---|---|---|
| `origin` | agiterra `tankloop/Nymbalyst` | Pull and push team code. **Most of your work.** |
| `upstream` | `Nimbalyst/nimbalyst` | Fetch upstream changes; base for PRs you file against the product. |
| `my-github` | your personal fork on GitHub | Push branches you want to PR upstream. |

You **do not** need access to anyone else's GitHub fork. Each person manages their own.

### Get a personal GitHub fork (one click)

If you haven't already, click "Fork" on https://github.com/Nimbalyst/nimbalyst on your GitHub account. That creates `github.com/<your-username>/nimbalyst`, which is what `my-github` above points at. Free, private to you, no permission grants needed from anyone.

### Get a Gitea token for shipping (optional, see "Releases" below)

Most people will never need to ship official builds. If you do, generate a token at agiterra → Settings → Applications, scope `repo`, then save it locally:

```bash
mkdir -p ~/.config/agiterra
echo "YOUR_TOKEN" > ~/.config/agiterra/token
chmod 600 ~/.config/agiterra/token
```

## Running dev mode safely (separate database, separate everything)

The packaged dogfood Nimbalyst you auto-update to *is your real install*: your team membership, your API keys, your workspaces, your database. You do **not** want dev experiments writing to that.

Use `dev:user2` for development work:

```bash
cd packages/electron
npm run dev:user2
```

This launches Nimbalyst with a completely isolated sandbox:

- Separate userData directory: `~/Library/Application Support/@nimbalyst/electron-user2`
- Separate database (its own PGLite instance)
- Separate settings, providers, API keys, team membership
- Separate Vite port (5274) so it doesn't collide with your packaged build

First launch feels like a fresh install. That's the point. Crash it, drop tables, install untrusted extensions, whatever. Your real install is on `0.58.22-dogfood` (or whatever the current shipped version is) and is untouched.

You can run dev and the packaged build side-by-side. They don't see each other.

To clean up the sandbox if it gets weird:

```bash
rm -rf "$HOME/Library/Application Support/@nimbalyst/electron-user2"
```

## Branch model

```
upstream/main   ── canonical Nimbalyst, the product. Read-only for us.
                          │
main (on agiterra) ── upstream/main + a small stack of fork-only commits
                      (deploy infra, dogfood release-channel UI, self-hosted
                      collab URLs, version bump). This is our team's trunk.
```

Brian periodically rebases `main` onto fresh `upstream/main` and ships. Don't try to do that yourself unless you've coordinated; force-pushing trunk from two machines makes a mess.

## Daily flow

### Pull latest before you start

```bash
git checkout main
git pull --ff-only
```

### Make a feature or fix branch

For a **dogfood-only change** (deploy infra, our self-hosted URLs, anything that's specific to how we run things):

```bash
git checkout -b fix/<short-name> main
# work, commit
git push -u origin fix/<short-name>
```

Open a PR on agiterra against `main`. Brian (or another reviewer) merges.

For an **upstream Nimbalyst fix** (something broken in the product itself that affects everyone, not just us):

```bash
git fetch upstream
git checkout -b fix/<short-name> upstream/main      # branch from upstream, not from main
# work, commit
git push -u my-github fix/<short-name>              # push to YOUR personal GitHub fork
```

Then open a PR on GitHub:

- Head: `<your-github-username>/nimbalyst:fix/<short-name>`
- Base: `Nimbalyst/nimbalyst:main`

Use `gh pr create --repo Nimbalyst/nimbalyst --base main --head <your-username>:fix/<short-name>` if you prefer the CLI.

When upstream merges, the fix flows back into our build automatically the next time Brian rebases trunk and ships.

## Filing bugs

| Where the bug is | Where to file it |
|---|---|
| Nimbalyst behavior (editor crashes, sync broken, AI providers misbehaving, anything in the product) | Issue on https://github.com/Nimbalyst/nimbalyst/issues |
| Our deployment (auto-updater can't find builds, signing problems on our hosted DMG, Cloudflare worker issues) | Tell Brian directly. It's our infrastructure, not upstream's product. |

When in doubt, file upstream. Most bugs that look like they're "in our build" are actually upstream bugs we just happen to hit first; filing them upstream gets them fixed for everyone.

## Building Nimbalyst locally

For testing your own code changes against a real packaged build (not dev mode):

```bash
cd packages/electron
npm run build:mac:local
```

This produces a signed DMG in `packages/electron/release/` without notarizing. You can install it locally for testing. **Don't ship a non-notarized build to the team** (the auto-updater rejects unsigned builds and macOS Gatekeeper warns the team on first launch).

If you ever want a fully notarized build (only useful if you're shipping), see "Releases" below.

## Releases

Shipping a notarized build to the team's `dogfood-current` is currently a single-person operation. **Brian ships official dogfood builds.** This is intentional, not a permission gap:

- Single-source-of-truth for what the team auto-updates to
- Apple Developer signing identity is per-account, and the auto-updater verifies signature continuity across versions
- If two people shipped builds with different signing identities, the updater would refuse the install

If you have an urgent fix that needs to ship before Brian can do it, push your branch, ping him, and he'll merge + ship. The whole loop usually takes a few minutes.

If we ever need a true "anyone can ship" model, that's a separate project: moving to an Apple Developer Team account with shared cert distribution. We'll do it when we need it, not before.

## Useful links

- **Team builds (rolling)**: https://git.agiterra.org/tankloop/Nymbalyst/releases/tag/dogfood-current
- **Versioned archive**: https://git.agiterra.org/tankloop/Nymbalyst/releases
- **Upstream Nimbalyst**: https://github.com/Nimbalyst/nimbalyst
- **Customization philosophy** (what work is in scope): [CUSTOMIZATION_WORKFLOW.md](./CUSTOMIZATION_WORKFLOW.md)
- **Engineering reference docs** (architecture, IPC, state, etc.): see the table in the root [CLAUDE.md](../CLAUDE.md)

## TL;DR

```
agiterra = our team's repo, our trunk
upstream Nimbalyst = the product, read-only
your personal GitHub fork = where you push branches you PR upstream

Use the team build for daily work (auto-updates from agiterra).
Use dev:user2 for development (isolated sandbox).
Push code to agiterra. PR upstream from your own fork.
Brian ships builds.
```

Peace B.Sweet
