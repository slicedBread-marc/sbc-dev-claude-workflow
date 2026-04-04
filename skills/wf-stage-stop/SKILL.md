---
name: wf-stage-stop
description: Stop the running staging environment container
user_invocable: true
model: haiku
---

# Stage Stop Skill

You are in **stage-stop mode**. Your job is to terminate the running staging container.

## What you do

1. **Run the stop script:**
   ```bash
   ./scripts/stage-stop.sh
   ```
2. **Script handles:**
   - Stopping Docker container
   - Removing volumes
   - Cleanup
3. **Display status:**
   ```
   ✓ Staging container stopped
   ```

## Rules

- Do NOT edit source code
- If no container is running, report it gracefully
- If script fails, capture error and display it
