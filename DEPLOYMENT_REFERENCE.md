# SBC Site Deployment Reference

## Deployment Architecture

```
develop branch
    ↓
GitHub Actions: deploy-staging.yml
    ↓
Fly.io Staging App: slicedbread-staging
    ↓
https://slicedbread-staging.fly.dev
```

```
main branch
    ↓
GitHub Actions: deploy.yml
    ↓
Fly.io Production App: slicedbread
    ↓
https://slicedbread.ca
```

## Branch → Deployment Mapping

| Branch | Environment | URL | Config File | Auto-Deploy |
|-|-|-|-|-|
| `develop` | Staging | https://slicedbread-staging.fly.dev | `fly.staging.toml` | On push |
| `main` | Production | https://slicedbread.ca | `fly.toml` | On push |

## CI/CD Pipeline

**Staging (`develop` branch):**
1. Checkout code
2. Setup .NET 10.0
3. Restore & build (Release config)
4. Run unit tests (exclude E2E)
5. Check for vulnerable packages
6. Deploy to Fly.io Staging

**Production (`main` branch):**
1. Checkout code
2. Setup .NET 10.0
3. Restore & build (Release config)
4. Run all tests (including E2E)
5. Check for vulnerable packages
6. Deploy to Fly.io Production

## Fly.io Configuration

| Setting | Staging | Production |
|-|-|-|
| App Name | slicedbread-staging | slicedbread |
| Region | yyz (Toronto) | yyz (Toronto) |
| Machine Size | shared-cpu-1x | shared-cpu-1x |
| Memory | 512MB | 512MB |
| Auto Stop | Disabled (min_machines=0) | Enabled (suspend) |
| Min Machines | 0 | 1 |
| Environment | Staging | Production |

## Workflow Notes

- **Both builds run full CI before deploying** — unsafe code doesn't reach either environment
- **Staging is lighter** — stops when not in use (cost saving)
- **Production is always warm** — at least 1 machine running
- **E2E tests only run before production** — smoke test after full build
- **Manual deployment available** — both workflows support `workflow_dispatch` for manual triggers
- **Feature branches don't auto-deploy** — only `develop` and `main` trigger deployments

## Proposed Multi-Branch Deployment Workflow

```
develop (planning only)
  - plans/briefs/
  - plans/ready/
  - plans/complete/ (from back-merges from main)

feature/* (implementation)
  - Code changes
  - Plan moves: ready/ → active/ → verify/
  - Progress + findings tracked
  - Local container testing via skill

release (pre-staging validation)
  - Feature branch merges here
  - Plan still in active/ state
  - Local container testing
  - Push to GitHub → auto-deploys to staging

main (production)
  - Plan moves: active/ → complete/
  - Back-merge to develop
  - Push to GitHub → auto-deploys to production
```

## Plan Locking Mechanism

When marking a plan as processing:

```
plans/active/my-feature/
  ├── plan.md (with status: locked, locked_by: feature/my-feature)
  ├── findings.md
  └── progress.md
```

Commit message: `plan: mark my-feature as locked (branch: feature/my-feature)`

This prevents duplicate work on `develop` while the feature is in flight.

## Docker Build Exclusions

Plans are tracked in git for history/context but excluded from production builds via `.dockerignore`:

```
plans/
.claude/
.git
.github
docs/
lessons/
bugs/
node_modules/
bin/
obj/
```

Result: Full git history with context, lean production containers.
