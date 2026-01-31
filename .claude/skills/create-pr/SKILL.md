# Create Pull Request

Create a pull request for the current branch.

## Steps

1. Check the current branch and ensure it's not main:
   ```bash
   git branch --show-current
   ```

2. Get the remote URL to determine repo owner and name:
   ```bash
   git remote get-url origin
   ```
   Parse the owner and repo from the URL (e.g., `github.com/v4vad/rayee.git` → owner: `v4vad`, repo: `rayee`)

3. Push the branch to remote if needed:
   ```bash
   git push -u origin $(git branch --show-current)
   ```

4. Get the commits on this branch (compared to main) to understand what changed:
   ```bash
   git log main..HEAD --oneline
   ```

5. Check if a PR already exists for this branch using GitHub MCP:
   - Use `mcp__plugin_github_github__list_pull_requests` with the owner, repo, and head branch
   - If a PR exists, report its URL instead of creating a new one

6. Create the PR using GitHub MCP tool `mcp__plugin_github_github__create_pull_request`:
   - `owner`: from step 2
   - `repo`: from step 2
   - `head`: current branch name
   - `base`: "main"
   - `title`: concise title under 70 characters
   - `body`: include Summary (bullet points) and Test plan (checklist)

7. Report the PR URL to the user.

## Notes

- If the branch is already pushed, skip the push step
- If a PR already exists for this branch, report that instead of creating a new one
- No need for `gh` CLI - we use GitHub MCP tools which are already authenticated
