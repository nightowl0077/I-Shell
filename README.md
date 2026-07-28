# I-Shell

**I-Shell** (short for *Intelligent Shell*) is a single script that upgrades your terminal with modern IDE-like features - inline autosuggestions, syntax highlighting, fuzzy history search, smart completions - for **zsh**, **bash**, or **fish**, on **macOS** (Homebrew), **Debian/Ubuntu/Kali** (apt), **Fedora/RHEL/Rocky/Alma** (dnf), **Arch/Manjaro** (pacman), and **openSUSE** (zypper). Optionally installs and themes [Ghostty](https://ghostty.org/), a GPU-accelerated terminal, and wires up a git-aware [Starship](https://starship.rs/) prompt.

Safe to re-run - every step checks before installing, appending, or removing.

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
- **tmux shortcut trainer mode** - installs tmux with a minimal always-visible bottom bar that rotates through a shortcut hint every 10 seconds (one tip at a time). Auto-starts in every terminal, only in Ghostty, or manually - your choice at install time. Prefix key, split keys, and vim-nav are all configurable.

## Requirements

- A supported package manager on `$PATH`:
  - **macOS**: [Homebrew](https://brew.sh/)
  - **Linux**: `apt` (Debian/Ubuntu/Kali), `dnf` (Fedora/RHEL/Rocky/Alma), `pacman` (Arch/Manjaro), or `zypper` (openSUSE)
- `git` and `make` (only if you use bash - needed to build `ble.sh`)
- `curl` (only if the Starship or Ghostty fallback installers run)
- For Ghostty on Arch: an AUR helper (`yay` or `paru`) since Ghostty is only on the AUR
- For Ghostty on Fedora: willingness to enable the `pgdev/ghostty` COPR (script asks before doing so)

> **Tested in Docker sandboxes**: Ubuntu 24.04, Fedora 41, Arch Linux, openSUSE Tumbleweed all pass the zsh install path. Plugin file paths are auto-detected at runtime (tries multiple candidate locations) rather than hardcoded per-distro, so distro layout changes don't break it.
>
> **openSUSE note**: the `shells:zsh-users` OBS community repo that used to host `zsh-autosuggestions` and `zsh-syntax-highlighting` has been retired. On openSUSE the installer instead offers to git-clone the two plugins directly from `github.com/zsh-users` into `~/.local/share/zsh-plugins/`. No third-party repo required.

## Usage

One script handles both install and uninstall:

```bash
git clone https://github.com/nightowl0077/I-Shell.git
cd I-Shell
chmod +x i-shell.sh

# --- install ---
./i-shell.sh                    # install for your current shell
./i-shell.sh install            # same as above
./i-shell.sh install zsh        # install for a specific shell (zsh|bash|fish)

# --- uninstall ---
./i-shell.sh uninstall          # uninstall for your current shell
./i-shell.sh uninstall bash     # uninstall for a specific shell

./i-shell.sh --help             # print usage
```

The installer will:
1. Detect your shell and package manager.
2. Install the plugins/tools listed above.
3. Append `source` lines to your shell rc file (only if not already present).
4. Ask whether to install Ghostty and, if yes, walk you through visual customization.
5. Reload your shell so the new features are live immediately.

The uninstaller will:
1. Strip the `source` / `eval` lines it added (a timestamped backup is saved as `<rcfile>.i-shell-bak.<epoch>` first).
2. Ask before uninstalling each package group (`zsh-autosuggestions`, `zsh-syntax-highlighting`, `zsh-completions`, `bash-completion`, `fzf`, `fish`).
3. Ask before deleting `~/.local/share/blesh` (the ble.sh install).
4. Ask before removing Starship (whether from your package manager or the community installer).
5. Ask before removing Ghostty; if you previously had a Ghostty config, offer to restore it from the newest `~/.config/ghostty/config.bak.*` backup.

Every uninstall step is opt-in, so you can drop things selectively (e.g. keep fzf but remove everything else).

## Keyboard shortcuts

The whole point of installing this stuff is these shortcuts.

### fzf - fuzzy pickers (all shells)

| Shortcut | What it does |
|---|---|
| `Ctrl-R` | Fuzzy-search your command **history**. Type any substring, hit Enter to run. |
| `Ctrl-T` | Fuzzy-search **files** under the current directory and paste the picked path into your command line. |
| `Alt-C` (macOS: `Esc-C` or `Option-C`) | Fuzzy-search **subdirectories** and `cd` into the one you pick. |

Inside any fzf picker: type to filter, `↑`/`↓` to move, `Enter` to accept, `Esc` to cancel, `Tab` to multi-select.

### Autosuggestions - the greyed-out ghost text

Applies to zsh (`zsh-autosuggestions`), bash (`ble.sh`), and fish (built-in). Suggestions come from your history and directory context.

| Shortcut | What it does |
|---|---|
| `→` (right arrow, cursor at end of line) | Accept the **whole** suggestion |
| `Ctrl-E` | Accept and jump to end of line |
| `Alt-F` / `Esc-F` | Accept just the **next word** of the suggestion |
| `Ctrl-U` | Clear the current line (dismisses the suggestion) |

### Completions

| Shortcut | What it does |
|---|---|
| `Tab` | Trigger completion or cycle through matches |
| `Tab Tab` (zsh) | Show the full menu of matches |
| `Shift-Tab` (zsh menu) | Cycle backwards through matches |

Tab now completes flags, subcommands, git branches, remote hosts, package names, and more - driven by `zsh-completions` / `bash-completion` / fish's built-in system.

### tmux (if you enabled trainer mode)

All shortcuts are preceded by the **prefix key** (`Ctrl-B` by default; you can pick `Ctrl-A` or `Ctrl-Space` at install time). Split keys default to `%` / `"` but can be swapped for the more mnemonic `|` / `-`.

| Shortcut | What it does |
|---|---|
| `prefix %` | Split pane vertically (side by side) |
| `prefix "` | Split pane horizontally (top / bottom) |
| `prefix ←→↑↓` | Move between panes |
| `prefix x` | Close the current pane |
| `prefix z` | Zoom pane to fullscreen (toggle) |
| `prefix c` | Create a new window |
| `prefix n` / `prefix p` | Next / previous window |
| `prefix ,` | Rename the current window |
| `prefix d` | Detach (session keeps running in the background - `tmux attach` to return) |
| `prefix [` | Enter scroll / copy mode (`q` to exit) |
| `prefix ?` | Show all keybindings |
| `prefix r` | Reload `~/.tmux.conf` |

The bottom bar rotates through these hints one at a time, so you don't have to memorize them all up front - one lands in front of your eyes every ~10 seconds until muscle memory takes over.

### Line editing (built-in but worth remembering)

| Shortcut | What it does |
|---|---|
| `Ctrl-A` / `Ctrl-E` | Jump to start / end of line |
| `Alt-B` / `Alt-F` | Move back / forward one word |
| `Ctrl-W` | Delete previous word |
| `Ctrl-U` / `Ctrl-K` | Delete to start / end of line |
| `Ctrl-L` | Clear the screen |

## What it edits

| Shell | File touched |
|---|---|
| zsh | `~/.zshrc` |
| bash | `~/.bashrc` (ble.sh init is **prepended**, since it must load early) |
| fish | `~/.config/fish/config.fish` |
| Ghostty | `~/.config/ghostty/config` (existing config is backed up to `config.bak.<timestamp>`) |
| tmux (trainer mode) | `~/.tmux.conf` (existing config is backed up to `~/.tmux.conf.i-shell-bak.<timestamp>`) and `~/.config/i-shell/tmux-tip.sh` (the rotating-tip script) |

Every append is guarded by a marker check, so re-running the script is idempotent.

## Notes

- **bash** has no first-class equivalent to `zsh-autosuggestions`, so the script installs [ble.sh](https://github.com/akinomyoga/ble.sh), which provides both autosuggestions and syntax highlighting. First install takes a minute (git clone + `make`).
- **fish** ships with autosuggestions and highlighting out of the box, so its setup is the shortest.
- **Ghostty on Debian/Ubuntu/Kali**: apt only carries Ghostty on Ubuntu 26.04+. On older releases the script offers to download the community `.deb` installer from [mkasberg/ghostty-ubuntu](https://github.com/mkasberg/ghostty-ubuntu) to a temp file so you can inspect it before running.
- Same pattern for the Starship fallback installer - it's downloaded to a temp file, then run only after you confirm. No blind `curl | bash`.
- If `compaudit` reports insecure zsh directories, the script fixes their permissions automatically.

## License

MIT
