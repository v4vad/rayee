# Merge to Main

Merge the current branch's pull request into main.

## Steps

1. Get the remote URL to determine repo owner and name:
   ```bash
   git remote get-url origin
   ```
   Parse the owner and repo from the URL (e.g., `github.com/v4vad/rayee.git` → owner: `v4vad`, repo: `rayee`)

2. Get the current branch name:
   ```bash
   git branch --show-current
   ```

3. Check if there's an open PR for the current branch using GitHub MCP:
   - Use `mcp__plugin_github_github__list_pull_requests` with owner, repo, head branch, and state "open"
   - If no PR exists, tell the user to create one first using `/create-pr`

4. Get PR details using `mcp__plugin_github_github__pull_request_read`:
   - `method`: "get"
   - Check if the PR is mergeable

5. If PR exists and is mergeable, merge it using `mcp__plugin_github_github__merge_pull_request`:
   - `owner`: from step 1
   - `repo`: from step 1
   - `pullNumber`: from step 3
   - `merge_method`: "squash" (keeps main history clean)

6. Delete the remote branch after merge (optional - can use bash):
   ```bash
   git push origin --delete <branch-name>
   ```

7. Switch back to main and pull:
   ```bash
   git checkout main && git pull
   ```

8. Delete local branch:
   ```bash
   git branch -d <branch-name>
   ```

9. Report success to the user.

## Notes

- If the PR has merge conflicts, report them and don't merge
- If the PR is not approved (when required), report that
- No need for `gh` CLI - we use GitHub MCP tools which are already authenticated
