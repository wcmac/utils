# utils

Personal utilities: shell scripts, Python scripts, Chrome extensions, and more.

## Structure

- `bin/` — executable shell scripts
- `zsh/` — zsh configuration, intended to be sourced from `~/.zshrc`
- `python/` — Python scripts
- `chrome-extensions/` — Chrome extension source code

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
