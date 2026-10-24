# utils

Personal command-line utilities and zsh configuration. This repo is public.

## Commit identity

Every commit must be authored **and** committed as

    Bill MacCartney <1048836+wcmac@users.noreply.github.com>

and every push must go to `https://github.com/wcmac/utils` as the `wcmac`
GitHub account.

- The identity is set repo-locally in `.git/config`. Never override it with
  `--author`, `GIT_AUTHOR_*` / `GIT_COMMITTER_*`, or `-c user.*`.
- Verify before **every** commit and every push, every time, not just once per
  session:

      git var GIT_AUTHOR_IDENT
      git var GIT_COMMITTER_IDENT

- Ask for explicit permission before every push. Each push needs its own yes.
  The hook below also forces a permission prompt for every push.
- Keep this repo's content, comments, and commit messages free of anything
  private. Never commit tokens or credentials.

### The hook

`.claude/hooks/check-git-identity.sh` (a PreToolUse hook on Bash, registered in
`.claude/settings.json`) enforces this and blocks with exit 2. If it blocks,
fix the cause; don't work around it. It checks commits and the other commands
that create commits (merge, pull, rebase, cherry-pick, revert, am); for pushes
it also checks `origin` and the credential account.

Tests: `.claude/hooks/test-check-git-identity.sh`. Run it after changing the hook.

**Known tradeoff:** the hook scans the whole command text. A Bash command that
merely *contains* identity-override text (`--author`, `GIT_AUTHOR_NAME=`, or
`git config user.name VALUE`) next to a git commit or push is blocked. Write
such text with the Write/Edit tools instead of a Bash heredoc, and reword
commit messages that need to mention it.

### Setting up a fresh clone

`.git/config` isn't versioned, so a new clone has neither the identity nor the
credential pin. Run once, in the clone:

    git config user.name "Bill MacCartney"
    git config user.email "1048836+wcmac@users.noreply.github.com"
    git config --add credential.helper ''
    git config --add credential.helper '!f() { test "$1" = get && echo username=wcmac && echo "password=$(gh auth token -u wcmac)"; }; f'

The empty `credential.helper` entry clears any inherited helper (such as the
macOS keychain one) so pushes always authenticate as `wcmac`. Then check with
`git var GIT_AUTHOR_IDENT` and run the tests.
