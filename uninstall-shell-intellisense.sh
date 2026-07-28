#!/usr/bin/env bash
#
# uninstall-shell-intellisense.sh
#
# Reverses everything setup-shell-intellisense.sh did:
#   - removes the source lines it added to your shell rc file
#   - uninstalls the packages it installed (with confirmation)
#   - deletes ble.sh, Starship, and Ghostty (each optional)
#   - restores the most recent Ghostty config backup, if one exists
#
# Usage:
#   ./uninstall-shell-intellisense.sh            # auto-detects your current shell
#   ./uninstall-shell-intellisense.sh zsh        # or force one
#   ./uninstall-shell-intellisense.sh bash
#   ./uninstall-shell-intellisense.sh fish
#
# Safe to re-run: every step checks before removing anything.

set -e

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[0;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[OK]${NC} $1"; }
warn()  { echo -e "${YELLOW}[..]${NC} $1"; }
fail()  { echo -e "${RED}[FAIL]${NC} $1"; exit 1; }

ask_yes_no() {
  local prompt="$1" answer
  read -r -p "$prompt [y/N]: " answer
  [[ "$answer" =~ ^[Yy]$ ]]
}

# ---------- Step 0: target shell ----------
TARGET_SHELL="$1"
if [ -z "$TARGET_SHELL" ]; then
  TARGET_SHELL="$(basename "$SHELL")"
  warn "No shell specified, detected default shell: $TARGET_SHELL"
fi

case "$TARGET_SHELL" in
  zsh|bash|fish) info "Target shell: $TARGET_SHELL" ;;
  *) fail "Unsupported shell '$TARGET_SHELL'. Use zsh, bash, or fish." ;;
esac

# ---------- Step 0b: package manager ----------
if command -v brew >/dev/null 2>&1; then
  PKG_MGR="brew"
  PKG_UNINSTALL="brew uninstall"
elif command -v apt >/dev/null 2>&1; then
  PKG_MGR="apt"
  PKG_UNINSTALL="sudo apt remove -y"
else
  warn "Neither Homebrew nor apt found — will only clean rc files, not uninstall packages."
  PKG_MGR="none"
fi
[ "$PKG_MGR" != "none" ] && info "Package manager: $PKG_MGR"

# is a package currently installed?
pkg_installed() {
  local pkg="$1"
  case "$PKG_MGR" in
    brew) brew list "$pkg" >/dev/null 2>&1 ;;
    apt)  dpkg -s "$pkg" >/dev/null 2>&1 ;;
    *)    return 1 ;;
  esac
}

uninstall_pkg() {
  local pkg="$1"
  pkg_installed "$pkg" || { info "$pkg not installed, skipping"; return; }
  warn "Removing $pkg..."
  $PKG_UNINSTALL "$pkg" || warn "Failed to remove $pkg (continuing)"
}

# Back up rc file, then strip any line matching the given extended regex.
# Also strips a "# --- xxx ---" header comment on the immediately preceding
# line and any single blank line before that, so the block goes cleanly.
strip_from_rc() {
  local rcfile="$1" pattern="$2"
  [ -f "$rcfile" ] || return 0
  grep -Eq "$pattern" "$rcfile" 2>/dev/null || return 0

  cp "$rcfile" "$rcfile.uninstall-bak.$(date +%s)"
  # awk: skip matching line; also retroactively drop a "# --- ... ---" comment
  # (and one blank line before it) that immediately precedes the match.
  awk -v pat="$pattern" '
    {
      lines[NR] = $0
    }
    END {
      skip[0] = 0
      for (i = 1; i <= NR; i++) {
        if (lines[i] ~ pat) {
          skip[i] = 1
          if (i-1 >= 1 && lines[i-1] ~ /^# --- .* ---$/) {
            skip[i-1] = 1
            if (i-2 >= 1 && lines[i-2] ~ /^[[:space:]]*$/) skip[i-2] = 1
          }
        }
      }
      for (i = 1; i <= NR; i++) if (!skip[i]) print lines[i]
    }
  ' "$rcfile" > "$rcfile.tmp" && mv "$rcfile.tmp" "$rcfile"
  info "Cleaned '$pattern' from $(basename "$rcfile")"
}

# =====================================================================
# ZSH
# =====================================================================
uninstall_zsh() {
  local ZSHRC="$HOME/.zshrc"

  echo "== Cleaning ~/.zshrc =="
  strip_from_rc "$ZSHRC" 'zsh-autosuggestions\.zsh'
  strip_from_rc "$ZSHRC" 'zsh-syntax-highlighting\.zsh'
  strip_from_rc "$ZSHRC" '^FPATH=.*zsh-completions'
  strip_from_rc "$ZSHRC" '^autoload -Uz compinit$'
  strip_from_rc "$ZSHRC" '^compinit$'
  strip_from_rc "$ZSHRC" 'starship init zsh'

  if [ "$PKG_MGR" != "none" ] && ask_yes_no "Uninstall zsh plugin packages (zsh-autosuggestions, zsh-syntax-highlighting, zsh-completions, fzf)?"; then
    for pkg in zsh-autosuggestions zsh-syntax-highlighting zsh-completions fzf; do
      uninstall_pkg "$pkg"
    done
  fi
}

# =====================================================================
# BASH
# =====================================================================
uninstall_bash() {
  local BASHRC="$HOME/.bashrc"

  echo "== Cleaning ~/.bashrc =="
  strip_from_rc "$BASHRC" 'blesh/ble\.sh'
  strip_from_rc "$BASHRC" 'ble-attach'
  strip_from_rc "$BASHRC" 'bash_completion\.sh'
  strip_from_rc "$BASHRC" 'key-bindings\.bash'
  strip_from_rc "$BASHRC" 'starship init bash'

  local BLESH_DIR="$HOME/.local/share/blesh"
  if [ -d "$BLESH_DIR" ] && ask_yes_no "Delete ble.sh install at $BLESH_DIR?"; then
    rm -rf "$BLESH_DIR"
    info "Removed $BLESH_DIR"
  fi

  if [ "$PKG_MGR" != "none" ] && ask_yes_no "Uninstall bash packages (bash-completion, fzf)?"; then
    if [ "$PKG_MGR" = "brew" ]; then
      uninstall_pkg "bash-completion@2"
    else
      uninstall_pkg "bash-completion"
    fi
    uninstall_pkg "fzf"
  fi
}

# =====================================================================
# FISH
# =====================================================================
uninstall_fish() {
  local FISH_CONF="$HOME/.config/fish/config.fish"

  echo "== Cleaning config.fish =="
  strip_from_rc "$FISH_CONF" 'fzf_key_bindings'
  strip_from_rc "$FISH_CONF" 'key-bindings\.fish'
  strip_from_rc "$FISH_CONF" 'starship init fish'

  if [ "$PKG_MGR" != "none" ] && ask_yes_no "Uninstall fzf?"; then
    uninstall_pkg "fzf"
  fi
  if [ "$PKG_MGR" != "none" ] && ask_yes_no "Uninstall the fish shell itself?"; then
    uninstall_pkg "fish"
  fi
}

# =====================================================================
# GHOSTTY (optional)
# =====================================================================
uninstall_ghostty() {
  local GHOSTTY_DIR="$HOME/.config/ghostty"
  local GHOSTTY_CONF="$GHOSTTY_DIR/config"

  if [ -f "$GHOSTTY_CONF" ]; then
    # Restore the most recent backup if one exists, otherwise offer to delete.
    local LATEST_BAK
    LATEST_BAK=$(ls -t "$GHOSTTY_CONF".bak.* 2>/dev/null | head -n1 || true)
    if [ -n "$LATEST_BAK" ] && ask_yes_no "Restore Ghostty config from backup $(basename "$LATEST_BAK")?"; then
      mv "$LATEST_BAK" "$GHOSTTY_CONF"
      info "Restored $GHOSTTY_CONF from backup"
    elif ask_yes_no "Delete Ghostty config file $GHOSTTY_CONF?"; then
      rm -f "$GHOSTTY_CONF"
      info "Removed $GHOSTTY_CONF"
    fi
  fi

  if command -v ghostty >/dev/null 2>&1 && ask_yes_no "Uninstall the Ghostty application?"; then
    if [ "$PKG_MGR" = "brew" ]; then
      brew uninstall --cask ghostty 2>/dev/null || warn "brew uninstall failed — remove Ghostty manually if it was installed another way."
    elif [ "$PKG_MGR" = "apt" ] && dpkg -s ghostty >/dev/null 2>&1; then
      sudo apt remove -y ghostty || warn "apt remove failed"
    else
      warn "Ghostty wasn't installed via a known package manager — remove it manually."
    fi
  fi
}

# =====================================================================
# STARSHIP (optional, cross-shell)
# =====================================================================
uninstall_starship() {
  command -v starship >/dev/null 2>&1 || return 0
  ask_yes_no "Uninstall Starship prompt?" || return 0
  if [ "$PKG_MGR" = "brew" ] && brew list starship >/dev/null 2>&1; then
    brew uninstall starship
  elif [ "$PKG_MGR" = "apt" ] && dpkg -s starship >/dev/null 2>&1; then
    sudo apt remove -y starship
  else
    # Installed via curl | sh — usually lives in /usr/local/bin or ~/.local/bin
    local STARSHIP_BIN
    STARSHIP_BIN=$(command -v starship)
    warn "Starship was installed outside a package manager. Removing $STARSHIP_BIN..."
    if [ -w "$STARSHIP_BIN" ]; then
      rm -f "$STARSHIP_BIN"
    else
      sudo rm -f "$STARSHIP_BIN"
    fi
  fi
  info "Starship removed"
}

# ---------- dispatch ----------
echo ""
warn "This will remove Intelligent Terminal's changes from your shell config."
warn "A timestamped backup of each rc file will be saved as <rcfile>.uninstall-bak.<epoch>."
ask_yes_no "Continue?" || { info "Aborted."; exit 0; }

case "$TARGET_SHELL" in
  zsh)  uninstall_zsh ;;
  bash) uninstall_bash ;;
  fish) uninstall_fish ;;
esac

echo ""
uninstall_starship
echo ""
if ask_yes_no "Also remove Ghostty and its config?"; then
  uninstall_ghostty
fi

echo ""
info "Done. Open a new terminal to load a clean shell environment."
