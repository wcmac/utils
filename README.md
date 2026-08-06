# utils

Personal command-line utilities and shell configuration.

## Structure

- `bin/` — executable scripts
- `zsh/` — zsh configuration, intended to be sourced from `~/.zshrc`

## Setup

Clone the repo:
```
git clone https://github.com/wcmac/utils.git ~/utils
```

Source the shared zsh config from `~/.zshrc`:
```
source ~/utils/zsh/common.zsh
```

This sets up PATH (including `~/utils/bin/`), aliases, prompt, and other shell configuration.
