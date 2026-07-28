# Intelligent Terminal

A single script that upgrades your terminal with modern IDE-like features — inline autosuggestions, syntax highlighting, fuzzy history search, smart completions — for **zsh**, **bash**, or **fish**, on **macOS** (Homebrew) and **Debian/Ubuntu/Kali** (apt). Optionally installs and themes [Ghostty](https://ghostty.org/), a GPU-accelerated terminal, and wires up a git-aware [Starship](https://starship.rs/) prompt.

Safe to re-run — it checks before installing or appending anything.

## What you get

| Feature | zsh | bash | fish |
|---|---|---|---|
| Inline autosuggestions (fish-style ghost text) | `zsh-autosuggestions` | `ble.sh` | built-in |
| Syntax highlighting as you type | `zsh-syntax-highlighting` | `ble.sh` | built-in |
| Fuzzy history + file search (`Ctrl-R`, `Ctrl-T`) | `fzf` | `fzf` | `fzf` |
| Rich tab completions | `zsh-completions` + `compinit` | `bash-completion` | built-in |

Optional add-ons:
- **Ghostty** terminal with a picker for theme (Catppuccin Mocha, Dracula, Nord, Gruvbox Dark, GitHub Dark), font family/size, and background transparency + blur.
- **Starship** prompt with git branch/status indicators.

## Requirements

- macOS with [Homebrew](https://brew.sh/), or Debian/Ubuntu/Kali with `apt`
- `git` and `make` (only if you use bash — needed to build `ble.sh`)
- `curl` (only if the Starship or Ghostty fallback installers run)

## Usage

```bash
git clone https://github.com/nightowl0077/Inteligent-Terminal.git
cd Inteligent-Terminal
chmod +x setup-shell-intellisense.sh

./setup-shell-intellisense.sh          # auto-detects your current shell
./setup-shell-intellisense.sh zsh      # or force one
./setup-shell-intellisense.sh bash
./setup-shell-intellisense.sh fish
```

The script will:
1. Detect your shell and package manager.
2. Install the plugins/tools listed above.
3. Append `source` lines to your shell rc file (only if not already present).
4. Ask whether to install Ghostty and, if yes, walk you through visual customization.
5. Reload your shell so the new features are live immediately.

## What it edits

| Shell | File touched |
|---|---|
| zsh | `~/.zshrc` |
| bash | `~/.bashrc` (ble.sh init is **prepended**, since it must load early) |
| fish | `~/.config/fish/config.fish` |
| Ghostty | `~/.config/ghostty/config` (existing config is backed up to `config.bak.<timestamp>`) |

Every append is guarded by a marker check, so re-running the script is idempotent.

## Notes

- **bash** has no first-class equivalent to `zsh-autosuggestions`, so the script installs [ble.sh](https://github.com/akinomyoga/ble.sh), which provides both autosuggestions and syntax highlighting. First install takes a minute (git clone + `make`).
- **fish** ships with autosuggestions and highlighting out of the box, so its setup is the shortest.
- **Ghostty on Debian/Ubuntu/Kali**: apt only carries Ghostty on Ubuntu 26.04+. On older releases the script falls back to the community `.deb` installer from [mkasberg/ghostty-ubuntu](https://github.com/mkasberg/ghostty-ubuntu).
- If `compaudit` reports insecure zsh directories, the script fixes their permissions automatically.

## Uninstall

Run the companion script — it reverses everything the installer did:

```bash
chmod +x uninstall-shell-intellisense.sh

./uninstall-shell-intellisense.sh          # auto-detects your current shell
./uninstall-shell-intellisense.sh zsh      # or force one
./uninstall-shell-intellisense.sh bash
./uninstall-shell-intellisense.sh fish
```

It will:
1. Strip the `source` / `eval` lines added to your shell rc file (a timestamped backup is saved as `<rcfile>.uninstall-bak.<epoch>` first).
2. Ask before uninstalling each set of packages (`zsh-autosuggestions`, `zsh-syntax-highlighting`, `zsh-completions`, `bash-completion`, `fzf`, `fish`).
3. Ask before deleting `~/.local/share/blesh` (the ble.sh install).
4. Ask before removing Starship (whether it came from your package manager or the `curl | sh` installer).
5. Ask before removing Ghostty; if you previously had a Ghostty config, offer to restore it from the newest `~/.config/ghostty/config.bak.*` backup.

Every step is opt-in, so you can uninstall selectively (e.g. keep fzf but drop everything else).

## License

MIT
