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
- `.claude/hooks/check-git-identity.sh` enforces this and blocks (exit 2). If it
  blocks, fix the cause; don't work around it.
- Keep this repo's content, comments, and commit messages free of anything
  private. Never commit tokens or credentials.
