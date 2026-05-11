---
name: Filing User Bug Reports
description: Process conversations or chat logs to identify reported bugs, search for existing GitHub issues, update existing issues when new undocumented details are discovered, and create new issues for untracked problems.
---

# Filing User Bug Reports

## Description
Process conversations or chat logs to identify reported bugs, search for existing GitHub issues, update existing issues when new undocumented details are discovered, and create new issues for untracked problems.

## When to Use
- After team discussions in chat channels (Telegram, Slack, Discord, etc.)
- When reviewing user feedback or support conversations
- During triage sessions to ensure all reported bugs are tracked
- When consolidating bug reports from multiple sources

## Process

### 1. Identify Reported Bugs
Read through the conversation and identify:
- **Explicit bug reports**: "There is a bug with...", "I'm experiencing an issue where..."
- **Problem statements**: "This isn't working...", "When I do X, Y happens instead of Z"
- **Confirmation from multiple users**: When multiple people report the same issue
- **Workarounds mentioned**: Often indicates an underlying bug

Look for:
- Specific reproduction steps
- Expected vs actual behavior
- Reproducibility (always, sometimes, specific conditions)
- Confirmation or denial by other users
- Workarounds or temporary fixes

### 2. Search for Existing Issues
For each identified bug, search GitHub using the `gh` CLI tool:

```bash
# Search by keywords from the bug description
gh issue list --repo <org>/<repo> --search "keyword1 keyword2" --limit 10 --json number,title,state,url

# Search by feature area
gh issue list --repo <org>/<repo> --search "feature area" --limit 10 --json number,title,state,url

# List issues with specific labels
gh issue list --repo <org>/<repo> --state open --label "bug" --limit 20 --json number,title,state,url
```

**Search Strategy:**
- Use multiple search queries with different keyword combinations
- Search for related features, not just exact matches
- Check both open and closed issues
- Review issue titles and bodies to confirm relevance

### 3. Categorize Findings
For each bug, determine:
- ✅ **Already Tracked**: Existing open issue found and no meaningful new information was discovered
- 📝 **Needs Existing Issue Update**: Existing issue found, but the conversation includes new undocumented details worth adding
- ⚠️ **Needs New Issue**: No existing issue found
- 🔄 **May Be Duplicate**: Similar issue exists but needs verification
- ❓ **Needs More Info**: Insufficient details to create or update an issue

### 4. Update Existing Issues or Create New Issues
For bugs that are already tracked but include new, undocumented details, update the existing GitHub issue with the newly gathered information. Add only net-new technical context such as clearer reproduction steps, environment details, frequency, workarounds, scope, or confirmations from additional users.

Example update command:

```bash
gh issue comment <issue-number> --repo <org>/<repo> --body "New information gathered from follow-up reports:\n\n- Updated reproduction steps: ...\n- Environment details: ...\n- Frequency: ...\n- Additional impact or workaround: ..."
```

If the existing issue body should be revised instead of just commented on, update it directly with `gh issue edit` so the canonical issue description stays current.

For bugs that need new tracking, create a GitHub issue using:

```bash
gh issue create --repo <org>/<repo> \
  --title "Clear, descriptive title" \
  --body "$(cat <<'EOF'
## Description
Clear description of the bug

## Steps to Reproduce
1. Step one
2. Step two
3. Step three

## Expected Behavior
What should happen

## Actual Behavior
What actually happens

## Environment
- Platform: iOS/Android/Web
- Version: X.Y.Z
- Source: Team chat discussion (Date)

## Additional Context
- Reproducibility: Always/Sometimes/Once
- Affected users: Multiple/Single
- Workaround: Yes/No
EOF
)" \
  --label "bug"
```

**Issue Writing Guidelines:**
- **No Personal Information**: Never include user names, email addresses, or identifying information
- **Be Specific**: Include concrete details, not vague descriptions
- **Include Context**: Platform, version, feature area
- **Note Reproducibility**: Is it consistent or intermittent?
- **Link Related Issues**: Reference existing issues if related
- **Use Appropriate Labels**: bug, feature-request, enhancement, etc.

### 5. Summary Report
Provide a summary showing:
- Total bugs identified
- Already tracked issues (with links)
- Newly created issues (with links)
- Issues needing more information

## Example Usage

```
User: Read this conversation and create issues for any bugs:
[paste conversation]

Agent:
1. Searches for existing issues related to mentioned problems
2. Identifies which bugs are already tracked
3. Creates new issues for untracked bugs
4. Provides summary with all issue links
```

## Best Practices

### During Identification
- Don't assume everything is a bug; some may be feature requests or questions
- Look for confirmation from multiple users or developers
- Note severity based on impact and frequency mentioned
- Capture exact error messages or symptoms

### During Search
- Use multiple search strategies (keywords, labels, feature areas)
- Check both open and closed issues (may have been fixed)
- Review issue bodies, not just titles
- Don't rely on a single search query

### During Issue Creation or Updates
- **Privacy First**: Strip all personal identifiers (names, emails, handles)
- Use neutral language ("A user reported..." not "John said...")
- Focus on technical details, not who reported it
- Include source context without identifying individuals
- Provide enough detail for developers to investigate
- Use clear, searchable titles
- Add reproduction steps when available
- When updating an existing issue, only add genuinely new information that is not already documented
- Prefer updating the canonical issue body when the new information improves the main description; otherwise add a concise comment
- Tag with appropriate labels for triage

### After Creation or Update
- Share issue links back to the team
- Note whether an issue was newly created or updated with additional information
- Update documentation if needed
- Consider priority/severity for team triage

## Common Pitfalls to Avoid
- Creating duplicate issues (search thoroughly first and update existing issues when appropriate)
- Including user names or personal information
- Vague titles like "Thing doesn't work"
- Missing platform/version information
- Creating issues for non-bugs (feature requests, questions)
- Not noting if the issue is reproducible or intermittent

## Output Format
When reporting findings, use this structure:

```
## Summary of Reported Bugs/Issues

### 1. [Bug Title] ✅ Already Tracked
- Status: [Link to existing issue]
- Description: Brief description
- Reporter: [Generic description, no names]

### 2. [Bug Title] 📝 Existing Issue Updated
- Status: Updated [Link to existing issue]
- New information added: Brief summary of the undocumented details

### 3. [Bug Title] ⚠️ Needs New Issue
- Description: Brief description
- Impact: User impact
- Status: Created [Link]

### Recommendations
- Updated existing issue #123 with additional context
- New issue created: #456
- Need more info for: [Description]
```

## Integration with Workflow
This skill integrates with:
- Team communication channels (Telegram, Slack, etc.)
- GitHub Issues via `gh` CLI
- Development workflow (triage, sprint planning)
- Documentation updates

## Notes
- Always respect user privacy; anonymize all reports
- Focus on technical merit, not reporter identity
- Maintain professional, objective language
- Cross-reference related issues when appropriate
- Consider creating a GitHub project or milestone for batched bugs from a single source
