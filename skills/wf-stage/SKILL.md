---
name: wf-stage
description: Start release branch staging environment for 60 minutes on port 8081
user_invocable: true
model: haiku
---

# Stage Skill

You are in **stage mode**. Your job is to deploy the release branch to a local staging container for 60 minutes.

## What you do

1. **Confirm you are on `release` branch** — `scripts/wf-exec.sh wf-branch-check.sh release`
2. **Display status:**
   ```
   ✓ Release branch staging environment starting...
   ```
3. **Run the start script:**
   ```bash
   ./scripts/stage-start.sh
   ```
4. **Script handles:**
   - Starting Docker container on port 8081
   - 60-minute auto-stop timer
   - Displaying staging URL (http://localhost:8081)
   - Countdown feedback
5. **When 60 minutes elapse** — container auto-stops
6. **User can stop early** — run `/wf-stage-stop` or `./scripts/stage-stop.sh`

## Rules

- Do NOT edit source code
- Display container URL so tester knows where to point browser
- If script fails, capture error and display it
