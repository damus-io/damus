---
name: github-triage
description: Bulk triage and cleanup of stale GitHub issues marked "Needs Recreation"
license: MIT
compatibility: opencode
metadata:
  audience: project-managers
  workflow: github
  domain: issue-management
---

# GitHub Issue Triage - Bulk "Needs Recreation" Cleanup

## What I do

Perform systematic bulk cleanup of stale "Needs Recreation" issues on GitHub that haven't been successfully reproduced for 4+ months. This workflow helps maintain a healthy issue backlog by closing likely-resolved bugs while providing clear paths for users to reopen if still reproducible.

## When to use me

Use this skill when:
- The GitHub issue backlog has accumulated many old "Needs Recreation" issues
- You need to reduce backlog size systematically
- You want to close stale reproduction requests without losing important bug reports
- It's been 4+ months since the last triage cleanup

## Prerequisites

Before starting, ensure you have:
1. **GitHub CLI (`gh`)** installed and authenticated
2. **Repository access** with permission to close issues
3. **Target repository** specified (e.g., `damus-io/damus`)
4. **Label name** for reproduction issues (e.g., "Needs recreation", "cannot reproduce")

## Workflow Overview

### Phase 1: Analysis & Discovery

1. **List all stale "Needs recreation" issues** (>4 months old) using a single `gh` filter:
   ```bash
   # Calculate date 4 months ago (example: 2025-10-20 if today is 2026-02-20)
   FOUR_MONTHS_AGO=$(date -v-4m +%Y-%m-%d)
   
   # Fetch issues older than 4 months with the "Needs recreation" label
   gh issue list --repo damus-io/damus \
     --label "Needs recreation" \
     --state open \
     --search "created:<$FOUR_MONTHS_AGO" \
     --limit 500 \
     --json number,title,createdAt,updatedAt,url
   ```

2. **Refine the batch** by reading each issue's description and comments:
   - Use `gh issue view <number> --repo damus-io/damus --json body,comments` to fetch details
   - **Keep in batch** if the issue lacks reliable reproduction steps (vague descriptions, missing steps, unverified reports)
   - **Remove from batch** if the issue is well-documented with clear, reliable reproduction steps
   - This ensures we only close issues that genuinely lack actionable information

3. **Present refined batch to user for review** before proceeding:
   - Show URL and title of each issue remaining in the refined batch
   - Give the user a chance to review and object before closing
   - Wait for user confirmation to proceed

### Phase 2: Execution Strategy

**IMPORTANT:** After presenting the refined batch to the user, wait for their confirmation before proceeding with closures.

#### Closure Approach
- **Skip notification phase** - Close immediately with automated comment
- **Close issues** using `gh issue close` (cancelled or not planned state)
- **Include reopening instructions** in every comment
- **Process in batches** of 7-8 issues to avoid overwhelming the system
- **Add closing comment before closing** - Always comment first, then close

#### Automated Comment Template

For all issues >4 months old:
```markdown
🤖 **Automated closure**

This issue is being closed because it has been marked "Needs recreation" for more than 4 months without successful reproduction. This suggests the issue may have been resolved in subsequent releases or is no longer reproducible.

**If you are still experiencing this issue with the latest version of Damus:**

Please reopen this issue and provide:
- Current Damus version number (from Settings → About)
- iOS/macOS version
- Detailed steps to reproduce
- Screenshots or video if applicable

Alternatively, you can open a new issue with the updated information.

Thank you for your bug report! 🙏
```

### Phase 3: Batch Processing

**IMPORTANT:** Only process issues from the refined batch (those lacking reliable repro steps that the user confirmed for closure).

Process issues in batches using parallel `gh` CLI calls:

**Batch Structure** (7-8 issues per batch):
1. **Post comments** to all issues in parallel
2. **Close issues** in parallel
3. **Verify completion** by checking exit codes
4. **Move to next batch**

**Example batch execution:**
```bash
# Batch 1: Post comments (parallel Bash calls)
gh issue comment 1234 --repo damus-io/damus --body "🤖 **Automated closure**..."
gh issue comment 5678 --repo damus-io/damus --body "🤖 **Automated closure**..."
# ... (5-6 more)

# Batch 2: Close issues (parallel)
gh issue close 1234 --repo damus-io/damus --reason "not planned"
gh issue close 5678 --repo damus-io/damus --reason "not planned"
# ... (5-6 more)
```

**Note:** All issues in the refined batch are >4 months old AND lack reliable reproduction steps.

**Note on close reason:**
- Use `--reason "not planned"` for stale reproduction requests
- Use `--reason "completed"` only if the issue was actually fixed

### Phase 4: Reporting

Generate final summary report including:
- **Total candidates found**: Initial count from date filter
- **Total removed**: Issues with reliable repro steps (kept open)
- **Total closed**: Final count of issues lacking repro steps
- **Links to all closed issues**

**Report Template:**
```markdown
## ✅ GitHub Triage Cleanup Complete

**Initial Candidates:** 45 issues (all >4 months old with "Needs recreation" label)
**Removed from batch:** 15 issues (had clear, reliable reproduction steps - kept open)
**Total Issues Closed:** 30 (lacked reliable repro steps)

**Closure Method:**
- Each issue analyzed for reproduction quality
- Refined batch reviewed and approved by user
- Automated comments posted to all issues via `gh` CLI
- All closed with reason "not planned"
- Users invited to reopen if reproducible

### All Closed Issues
1. [#1234](url) - Title
2. [#5678](url) - Title
...

### Issues Kept Open (Well-Documented)
1. [#2345](url) - Title (has clear repro steps)
2. [#6789](url) - Title (detailed description with screenshots)
...

```

## Key Principles

### Do's ✅
- **Read issue details** - Review descriptions and comments to assess reproduction quality
- **Refine the batch** - Only keep issues lacking reliable repro steps
- **Present batch for review** - Show URLs and titles to user before closing
- **Wait for confirmation** - Get user approval before proceeding with closures
- **Use gh CLI** - All operations via `gh issue` commands
- **Batch operations** - Process 7-8 issues at a time
- **Parallel calls** - Use Bash tool in parallel when independent
- **Clear messaging** - Include reopening instructions in every comment
- **Use simple messaging** - State "more than 4 months" rather than exact ages
- **Comment before closing** - Always add comment first, then close

### Don'ts ❌
- **Don't skip issue analysis** - Always read descriptions and comments to assess quality
- **Don't close well-documented issues** - Remove from batch if clear repro steps exist
- **Don't proceed without user review** - Present refined batch and wait for confirmation
- **Don't batch comments + closes together** - Do comments first, then closes
- **Don't skip assigned issues** - Close them too if stale (unless maintainer requests otherwise)
- **Don't calculate exact ages** - Simply state "more than 4 months old"
- **Don't forget reopening instructions** - Critical for user trust
- **Don't close without commenting** - Always explain why

## Common Adjustments

### Adjust Age Thresholds
If your team has different staleness criteria, adjust the date calculation:
- **Conservative**: 6+ months old: `date -v-6m +%Y-%m-%d`
- **Aggressive**: 2+ months old: `date -v-2m +%Y-%m-%d`
- **Standard** (recommended): 4+ months old: `date -v-4m +%Y-%m-%d`

## Troubleshooting

### Rate Limiting
If you hit GitHub API rate limits:
- Reduce batch size to 5 issues
- Add 2-3 second delays between batches
- Use fewer parallel calls
- Check rate limit: `gh api rate_limit`

### Permission Errors
If you can't close issues:
- Verify authentication: `gh auth status`
- Check repository access: `gh repo view owner/repo`
- Ensure you have triage or write permissions

### Assigned Issues
If assignees object to closures:
- Offer to keep their issues open
- Or add them to "Keep open" list
- Document exceptions in report

### gh CLI Not Found
Install GitHub CLI:
- macOS: `brew install gh`
- Linux: See https://github.com/cli/cli#installation
- Windows: `winget install GitHub.cli`

## Example Session

**Input:** "Close all stale 'Needs recreation' issues older than 4 months in damus-io/damus"

**Agent actions:**
1. Runs `gh issue list` with date filter to fetch all "Needs recreation" issues >4 months old (finds 45 initial candidates)
2. Reads each issue's description and comments using `gh issue view` to assess reproduction quality
3. Refines batch by removing 15 well-documented issues with clear repro steps
4. Presents refined batch of 30 issues to user with URLs and titles for review
5. Waits for user confirmation to proceed
6. After confirmation, processes in 4 batches of 7-8 issues each:
   - Batch 1: 8 issues (oldest)
   - Batch 2: 8 issues
   - Batch 3: 7 issues
   - Batch 4: 7 issues (newest qualifying)
7. Posts automated comment to each issue using `gh issue comment` (stating "more than 4 months old")
8. Closes all issues using `gh issue close --reason "not planned"`
9. Generates summary report with links

**Output:** Clean issue backlog, 30 closed issues (lacking repro steps) with clear reopening path, 15 well-documented issues kept open

## References

- **GitHub CLI Documentation**: https://cli.github.com/manual/
- **gh issue commands**: https://cli.github.com/manual/gh_issue
- **Damus AGENTS.md**: Team-specific contribution standards
