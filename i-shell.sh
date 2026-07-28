#!/usr/bin/env bash
#
# i-shell.sh  (I-Shell = Intelligent Shell)
#
# One script, two actions:
#   install    Adds autosuggestions, syntax highlighting, fuzzy search, and
#              completions to zsh / bash / fish. Optionally installs Ghostty
#              and a git-aware Starship prompt.
#   uninstall  Reverses everything install did (rc lines, packages, ble.sh,
#              Starship, Ghostty). Every step is opt-in.
#
# Usage:
#   ./i-shell.sh                          # install, auto-detect current shell
#   ./i-shell.sh install                  # same as above
#   ./i-shell.sh install zsh              # install and force a specific shell
#   ./i-shell.sh uninstall                # uninstall for current shell
#   ./i-shell.sh uninstall bash           # uninstall and force a specific shell
#
# Safe to re-run: every step checks before installing, appending, or removing.

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

# ---------- Arg parsing: [install|uninstall] [zsh|bash|fish] ----------
ACTION="install"
case "$1" in
  install|uninstall) ACTION="$1"; shift ;;
  -h|--help|help)
    sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
    exit 0 ;;
esac

TARGET_SHELL="$1"
if [ -z "$TARGET_SHELL" ]; then
  TARGET_SHELL="$(basename "$SHELL")"
  warn "No shell specified, detected default shell: $TARGET_SHELL"
fi

case "$TARGET_SHELL" in
  zsh|bash|fish) info "Action: $ACTION   Target shell: $TARGET_SHELL" ;;
  *) fail "Unsupported shell '$TARGET_SHELL'. Use zsh, bash, or fish." ;;
esac

# ---------- Package manager detection ----------
if command -v brew >/dev/null 2>&1; then
  PKG_MGR="brew"
  PKG_INSTALL="brew install"
  PKG_UNINSTALL="brew uninstall"
  PKG_PREFIX="$(brew --prefix)"
elif command -v apt >/dev/null 2>&1; then
  PKG_MGR="apt"
  PKG_INSTALL="sudo apt install -y"
  PKG_UNINSTALL="sudo apt remove -y"
  PKG_PREFIX="/usr"
elif command -v dnf >/dev/null 2>&1; then
  PKG_MGR="dnf"
  PKG_INSTALL="sudo dnf install -y"
  PKG_UNINSTALL="sudo dnf remove -y"
  PKG_PREFIX="/usr"
elif command -v pacman >/dev/null 2>&1; then
  PKG_MGR="pacman"
  PKG_INSTALL="sudo pacman -S --noconfirm --needed"
  PKG_UNINSTALL="sudo pacman -Rs --noconfirm"
  PKG_PREFIX="/usr"
elif command -v zypper >/dev/null 2>&1; then
  PKG_MGR="zypper"
  PKG_INSTALL="sudo zypper install -y"
  PKG_UNINSTALL="sudo zypper remove -y"
  PKG_PREFIX="/usr"
else
  if [ "$ACTION" = "install" ]; then
    fail "No supported package manager found. This script supports brew (macOS), apt (Debian/Ubuntu/Kali), dnf (Fedora/RHEL/Rocky), pacman (Arch), and zypper (openSUSE)."
  fi
  PKG_MGR="none"
  warn "No supported package manager found - uninstall will only clean rc files, not remove packages."
fi
[ "$PKG_MGR" != "none" ] && info "Package manager: $PKG_MGR"

pkg_installed() {
  local pkg="$1"
  case "$PKG_MGR" in
    brew)          brew list "$pkg" >/dev/null 2>&1 ;;
    apt)           dpkg -s "$pkg" >/dev/null 2>&1 ;;
    dnf|zypper)    rpm -q "$pkg" >/dev/null 2>&1 ;;
    pacman)        pacman -Q "$pkg" >/dev/null 2>&1 ;;
    *)             return 1 ;;
  esac
}

# Print the first path that exists from the args, or empty string.
# Always returns 0 so callers can capture the result under `set -e`
# without needing `|| true` on every assignment.
find_first() {
  local p
  for p in "$@"; do
    if [ -e "$p" ]; then
      printf '%s' "$p"
      return 0
    fi
  done
  return 0
}

install_pkg() {
  local pkg="$1"
  pkg_installed "$pkg" && { info "$pkg already installed"; return; }
  warn "Installing $pkg..."
  $PKG_INSTALL "$pkg" || fail "Failed to install $pkg"
  info "$pkg installed"
}

uninstall_pkg() {
  local pkg="$1"
  pkg_installed "$pkg" || { info "$pkg not installed, skipping"; return; }
  warn "Removing $pkg..."
  $PKG_UNINSTALL "$pkg" || warn "Failed to remove $pkg (continuing)"
}

add_line_if_missing() {
  local rcfile="$1" marker="$2" block="$3"
  if grep -qF "$marker" "$rcfile" 2>/dev/null; then
    info "Already present in $(basename "$rcfile"): $marker"
  else
    echo "$block" >> "$rcfile"
    info "Added to $(basename "$rcfile"): $marker"
  fi
}

# Backs up rc file, then strips lines matching the given extended regex.
# Also drops a "# --- xxx ---" header (and one blank line above it) that
# immediately precedes the matched line, so blocks go cleanly.
strip_from_rc() {
  local rcfile="$1" pattern="$2"
  [ -f "$rcfile" ] || return 0
  grep -Eq "$pattern" "$rcfile" 2>/dev/null || return 0

  cp "$rcfile" "$rcfile.i-shell-bak.$(date +%s)"
  awk -v pat="$pattern" '
    { lines[NR] = $0 }
    END {
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
# INSTALL — ZSH
# =====================================================================
install_zsh() {
  local ZSHRC="$HOME/.zshrc"
  touch "$ZSHRC"

  # Install zsh itself first - most distros pull it as a dep of zsh-autosuggestions,
  # but we shouldn't rely on that (openSUSE uses git-clone fallback below).
  install_pkg "zsh"

  # Only brew ships zsh-completions as a straightforwardly-named separate package.
  # apt and dnf don't package it; pacman/zypper do but naming varies - the built-in
  # completions in /usr/share/zsh/site-functions cover the common cases on Linux.
  local zsh_pkgs="zsh-autosuggestions zsh-syntax-highlighting fzf"
  if [ "$PKG_MGR" = "brew" ]; then
    zsh_pkgs="$zsh_pkgs zsh-completions"
  fi

  # openSUSE's default repos don't ship the zsh plugins (and the old OBS repo was
  # retired). Fall back to git-cloning them into ~/.local/share/zsh-plugins - they're
  # pure zsh scripts, no build step, same pattern as ble.sh for bash.
  local ZSH_PLUGIN_DIR="$HOME/.local/share/zsh-plugins"
  local git_clone_plugins="no"
  if [ "$PKG_MGR" = "zypper" ] && ! zypper --non-interactive info zsh-autosuggestions 2>/dev/null | grep -q "^Name"; then
    warn "openSUSE's default repos don't include zsh-autosuggestions / zsh-syntax-highlighting."
    if ask_yes_no "Install them from source (git clone into ~/.local/share/zsh-plugins)?"; then
      git_clone_plugins="yes"
      # Drop them from the package-install list since we're handling them differently
      zsh_pkgs="fzf"
    else
      fail "Cannot install zsh plugins. Add them yourself or use bash/fish instead."
    fi
  fi

  for pkg in $zsh_pkgs; do install_pkg "$pkg"; done

  if [ "$git_clone_plugins" = "yes" ]; then
    mkdir -p "$ZSH_PLUGIN_DIR"
    for repo in zsh-autosuggestions zsh-syntax-highlighting; do
      if [ -d "$ZSH_PLUGIN_DIR/$repo/.git" ]; then
        info "$repo already cloned"
      else
        warn "Cloning $repo..."
        git clone --depth 1 "https://github.com/zsh-users/$repo.git" "$ZSH_PLUGIN_DIR/$repo" \
          || fail "git clone of $repo failed"
        info "$repo cloned to $ZSH_PLUGIN_DIR/$repo"
      fi
    done
  fi

  # Auto-detect installed plugin paths across distros (including git-clone fallback)
  local SUGGEST HIGHLIGHT COMP_DIR
  SUGGEST=$(find_first \
    "$PKG_PREFIX/share/zsh-autosuggestions/zsh-autosuggestions.zsh" \
    "/usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh" \
    "/usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh" \
    "$ZSH_PLUGIN_DIR/zsh-autosuggestions/zsh-autosuggestions.zsh")
  HIGHLIGHT=$(find_first \
    "$PKG_PREFIX/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" \
    "/usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" \
    "/usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" \
    "$ZSH_PLUGIN_DIR/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh")
  COMP_DIR=$(find_first \
    "$PKG_PREFIX/share/zsh-completions" \
    "/usr/share/zsh-completions" \
    "/usr/share/zsh/site-functions")

  echo "== fzf key bindings =="
  if [ -f "$HOME/.fzf.zsh" ]; then
    info "fzf shell integration already set up"
  elif [ -d "$PKG_PREFIX/opt/fzf" ]; then
    warn "Running fzf install script (answer its prompts with 'y')..."
    "$PKG_PREFIX/opt/fzf/install"
  else
    # Linux distros ship fzf integration files at various paths - source whichever is present
    add_line_if_missing "$ZSHRC" "i-shell fzf key-bindings" "
# --- fzf key bindings ---
for f in /usr/share/doc/fzf/examples/key-bindings.zsh \\
         /usr/share/doc/fzf/examples/completion.zsh \\
         /usr/share/fzf/shell/key-bindings.zsh \\
         /usr/share/fzf/shell/completion.zsh \\
         /usr/share/fzf/key-bindings.zsh \\
         /usr/share/fzf/completion.zsh; do
  [ -f \"\$f\" ] && source \"\$f\"
done"
  fi

  echo "== Updating ~/.zshrc =="
  if [ -n "$COMP_DIR" ]; then
    add_line_if_missing "$ZSHRC" "zsh-completions" "
# --- completions ---
FPATH=$COMP_DIR:\$FPATH
autoload -Uz compinit
compinit"
  fi
  if [ -n "$SUGGEST" ]; then
    add_line_if_missing "$ZSHRC" "zsh-autosuggestions.zsh" "
# --- autosuggestions ---
source $SUGGEST"
  else
    warn "zsh-autosuggestions file not found in known paths - skipped adding source line"
  fi
  if [ -n "$HIGHLIGHT" ]; then
    add_line_if_missing "$ZSHRC" "zsh-syntax-highlighting.zsh" "
# --- syntax highlighting (must stay last) ---
source $HIGHLIGHT"
  else
    warn "zsh-syntax-highlighting file not found in known paths - skipped adding source line"
  fi

  echo "== Checking for insecure directories =="
  local INSECURE
  INSECURE=$(compaudit 2>/dev/null || true)
  if [ -z "$INSECURE" ]; then
    info "No insecure directories"
  else
    warn "Fixing insecure directory permissions..."
    echo "$INSECURE" | tail -n +2 | while read -r dir; do
      [ -n "$dir" ] && chmod go-w "$dir" && info "Fixed: $dir"
    done
  fi

  echo "== Validating =="
  [ -n "$SUGGEST" ] && [ -f "$SUGGEST" ] && info "autosuggestions file present ($SUGGEST)" || warn "autosuggestions file not detected - check your distro's package layout"
  [ -n "$HIGHLIGHT" ] && [ -f "$HIGHLIGHT" ] && info "syntax-highlighting file present ($HIGHLIGHT)" || warn "syntax-highlighting file not detected - check your distro's package layout"
  grep -qF "zsh-autosuggestions" "$ZSHRC" && info "autosuggestions referenced in .zshrc"
  grep -qF "zsh-syntax-highlighting" "$ZSHRC" && info "syntax-highlighting referenced in .zshrc"

  echo -e "${GREEN}zsh install complete.${NC} Reloading..."
  exec zsh -l
}

# =====================================================================
# INSTALL — BASH
# =====================================================================
install_bash() {
  local BASHRC="$HOME/.bashrc"
  touch "$BASHRC"

  if [ "$PKG_MGR" = "brew" ]; then
    install_pkg "bash-completion@2"
    install_pkg "fzf"
  else
    install_pkg "bash-completion"
    install_pkg "fzf"
  fi

  echo "== fzf key bindings =="
  if [ -f "$HOME/.fzf.bash" ]; then
    info "fzf shell integration already set up"
  elif [ -d "$PKG_PREFIX/opt/fzf" ]; then
    warn "Running fzf install script (answer its prompts with 'y')..."
    "$PKG_PREFIX/opt/fzf/install"
  else
    add_line_if_missing "$BASHRC" "i-shell fzf key-bindings" "
# --- fzf key bindings ---
for f in /usr/share/doc/fzf/examples/key-bindings.bash \\
         /usr/share/doc/fzf/examples/completion.bash \\
         /usr/share/fzf/shell/key-bindings.bash \\
         /usr/share/fzf/shell/completion.bash \\
         /usr/share/fzf/key-bindings.bash \\
         /usr/share/fzf/completion.bash; do
  [ -f \"\$f\" ] && source \"\$f\"
done"
  fi

  echo "== Installing ble.sh (autosuggestions + syntax highlighting for bash) =="
  local BLESH_DIR="$HOME/.local/share/blesh"
  if [ -f "$BLESH_DIR/ble.sh" ]; then
    info "ble.sh already installed"
  else
    warn "Cloning and building ble.sh (this takes a minute)..."
    command -v make >/dev/null 2>&1 || fail "'make' is required to build ble.sh. Install build-essential (apt) or Xcode CLI tools (brew)."
    local TMP_DIR
    TMP_DIR=$(mktemp -d)
    git clone --recursive --depth 1 --shallow-submodules \
      https://github.com/akinomyoga/ble.sh.git "$TMP_DIR/ble.sh" || fail "git clone of ble.sh failed"
    make -C "$TMP_DIR/ble.sh" install PREFIX="$HOME/.local" || fail "ble.sh build failed"
    rm -rf "$TMP_DIR"
    info "ble.sh installed to $BLESH_DIR"
  fi

  echo "== Updating ~/.bashrc =="
  if ! grep -qF "blesh/ble.sh" "$BASHRC"; then
    { echo "[[ \$- == *i* ]] && source \"$BLESH_DIR/ble.sh\" --noattach"; cat "$BASHRC"; } > "$BASHRC.tmp"
    mv "$BASHRC.tmp" "$BASHRC"
    info "Prepended ble.sh init to .bashrc"
  else
    info "ble.sh already referenced in .bashrc"
  fi
  add_line_if_missing "$BASHRC" "bash_completion" '[ -f /opt/homebrew/etc/profile.d/bash_completion.sh ] && source /opt/homebrew/etc/profile.d/bash_completion.sh'
  add_line_if_missing "$BASHRC" "ble-attach" '[[ ${BLE_VERSION-} ]] && ble-attach'

  echo "== Validating =="
  [ -f "$BLESH_DIR/ble.sh" ] && info "ble.sh present" || fail "ble.sh missing"
  grep -qF "blesh/ble.sh" "$BASHRC" && info "ble.sh referenced in .bashrc"

  echo -e "${GREEN}bash install complete.${NC} Reloading..."
  exec bash -l
}

# =====================================================================
# INSTALL — FISH
# =====================================================================
install_fish() {
  install_pkg "fish"
  install_pkg "fzf"

  local FISH_CONF_DIR="$HOME/.config/fish"
  mkdir -p "$FISH_CONF_DIR"
  local FISH_CONF="$FISH_CONF_DIR/config.fish"
  touch "$FISH_CONF"

  info "fish has autosuggestions and syntax highlighting built in — no plugins needed"

  echo "== Adding fzf key bindings for fish =="
  local FZF_FISH_BINDINGS
  FZF_FISH_BINDINGS=$(find_first \
    "$PKG_PREFIX/opt/fzf/shell/key-bindings.fish" \
    "/usr/share/doc/fzf/examples/key-bindings.fish" \
    "/usr/share/fzf/shell/key-bindings.fish" \
    "/usr/share/fzf/key-bindings.fish")
  if [ -n "$FZF_FISH_BINDINGS" ]; then
    add_line_if_missing "$FISH_CONF" "fzf_key_bindings" "source $FZF_FISH_BINDINGS
fzf_key_bindings"
  else
    warn "fzf fish bindings file not found in known paths - see https://github.com/junegunn/fzf#fish"
  fi

  echo "== Validating =="
  command -v fish >/dev/null 2>&1 && info "fish installed" || fail "fish not found after install"

  echo -e "${GREEN}fish install complete.${NC}"
  warn "To make fish your default shell: chsh -s \$(which fish)"
  echo "Launching a fish session now..."
  exec fish
}

# =====================================================================
# INSTALL — GHOSTTY (optional)
# =====================================================================
install_ghostty() {
  if command -v ghostty >/dev/null 2>&1; then
    info "Ghostty already installed"
    return
  fi

  case "$PKG_MGR" in
    brew)
      warn "Installing Ghostty via Homebrew cask..."
      brew install --cask ghostty || fail "Ghostty install failed"
      ;;
    apt)
      if apt list --installable 2>/dev/null | grep -q '^ghostty/'; then
        warn "Installing Ghostty via apt..."
        sudo apt install -y ghostty || fail "Ghostty install failed"
      else
        local INSTALLER_URL="https://raw.githubusercontent.com/mkasberg/ghostty-ubuntu/HEAD/install.sh"
        warn "Ghostty isn't in this distro's apt repos yet - the community installer is at:"
        warn "  $INSTALLER_URL"
        ask_yes_no "Download it to a temp file so you can inspect, then run it?" \
          || fail "Skipped Ghostty install. See https://github.com/mkasberg/ghostty-ubuntu for manual steps."
        local INSTALLER_TMP
        INSTALLER_TMP=$(mktemp -t ghostty-install.XXXXXX.sh)
        curl -fsSL "$INSTALLER_URL" -o "$INSTALLER_TMP" || fail "Failed to download installer"
        info "Downloaded to $INSTALLER_TMP - inspect it in another terminal if you like."
        ask_yes_no "Run $INSTALLER_TMP now?" || { rm -f "$INSTALLER_TMP"; fail "Skipped Ghostty install."; }
        bash "$INSTALLER_TMP" || { rm -f "$INSTALLER_TMP"; fail "Ghostty community installer failed."; }
        rm -f "$INSTALLER_TMP"
      fi
      ;;
    dnf)
      warn "Ghostty isn't in the official Fedora repos. It's available via the pgdev/ghostty COPR (community-maintained third-party repo)."
      ask_yes_no "Enable the pgdev/ghostty COPR and install Ghostty?" \
        || fail "Skipped Ghostty install. See https://ghostty.org/download for manual steps."
      sudo dnf copr enable -y pgdev/ghostty || fail "Enabling COPR failed"
      sudo dnf install -y ghostty || fail "Ghostty install failed"
      ;;
    pacman)
      if command -v yay >/dev/null 2>&1; then
        warn "Installing Ghostty from AUR via yay..."
        yay -S --noconfirm ghostty || fail "Ghostty install failed"
      elif command -v paru >/dev/null 2>&1; then
        warn "Installing Ghostty from AUR via paru..."
        paru -S --noconfirm ghostty || fail "Ghostty install failed"
      else
        fail "Ghostty is only on the AUR. Install 'yay' or 'paru' first, or grab Ghostty manually: https://ghostty.org/download"
      fi
      ;;
    zypper)
      fail "Ghostty isn't packaged for openSUSE. See https://ghostty.org/download for manual install instructions."
      ;;
  esac

  command -v ghostty >/dev/null 2>&1 && info "Ghostty installed" || warn "Ghostty command not found on PATH yet - you may need to open a new terminal"
}

configure_ghostty() {
  local GHOSTTY_DIR="$HOME/.config/ghostty"
  local GHOSTTY_CONF="$GHOSTTY_DIR/config"
  mkdir -p "$GHOSTTY_DIR"

  if [ -f "$GHOSTTY_CONF" ]; then
    cp "$GHOSTTY_CONF" "$GHOSTTY_CONF.bak.$(date +%s)"
    info "Backed up existing config to $(basename "$GHOSTTY_CONF").bak.*"
  else
    touch "$GHOSTTY_CONF"
  fi

  echo ""
  echo "Ghostty visual customization (optional) — press Enter on any prompt to skip it."
  echo ""
  echo "Pick a theme:"
  echo "  1) catppuccin-mocha (dark, popular)"
  echo "  2) dracula"
  echo "  3) nord"
  echo "  4) gruvbox-dark"
  echo "  5) GitHub Dark Default"
  echo "  6) skip / keep default"
  read -r -p "Choice [1-6]: " theme_choice
  case "$theme_choice" in
    1) add_line_if_missing "$GHOSTTY_CONF" "theme =" "theme = catppuccin-mocha" ;;
    2) add_line_if_missing "$GHOSTTY_CONF" "theme =" "theme = dracula" ;;
    3) add_line_if_missing "$GHOSTTY_CONF" "theme =" "theme = nord" ;;
    4) add_line_if_missing "$GHOSTTY_CONF" "theme =" "theme = gruvbox-dark" ;;
    5) add_line_if_missing "$GHOSTTY_CONF" "theme =" "theme = GitHub Dark Default" ;;
    *) info "Skipping theme (using default)" ;;
  esac

  read -r -p "Font family (e.g. 'JetBrains Mono', blank to skip): " font_choice
  if [ -n "$font_choice" ]; then
    add_line_if_missing "$GHOSTTY_CONF" "font-family =" "font-family = \"$font_choice\""
  fi

  read -r -p "Font size (e.g. 14, blank to skip): " font_size
  if [ -n "$font_size" ]; then
    add_line_if_missing "$GHOSTTY_CONF" "font-size =" "font-size = $font_size"
  fi

  if ask_yes_no "Enable background transparency + blur (macOS/KDE)?"; then
    add_line_if_missing "$GHOSTTY_CONF" "background-opacity" "background-opacity = 0.92
background-blur = true"
  fi

  if ask_yes_no "Add a git-aware prompt (shows branch/status) via Starship — works in zsh/bash/fish?"; then
    if command -v starship >/dev/null 2>&1; then
      info "starship already installed ($(command -v starship))"
    elif ! install_pkg "starship" 2>/dev/null; then
      local SS_URL="https://starship.rs/install.sh"
      warn "starship isn't packaged here — the official installer is at $SS_URL"
      ask_yes_no "Download it to a temp file so you can inspect, then run it?" \
        || fail "Skipped starship install."
      local SS_TMP
      SS_TMP=$(mktemp -t starship-install.XXXXXX.sh)
      curl -fsSL "$SS_URL" -o "$SS_TMP" || fail "Failed to download starship installer"
      info "Downloaded to $SS_TMP — inspect it if you like."
      ask_yes_no "Run $SS_TMP now?" || { rm -f "$SS_TMP"; fail "Skipped starship install."; }
      sh "$SS_TMP" -- -y || { rm -f "$SS_TMP"; fail "starship install failed"; }
      rm -f "$SS_TMP"
    fi
    case "$TARGET_SHELL" in
      zsh)  add_line_if_missing "$HOME/.zshrc" 'starship init zsh' 'eval "$(starship init zsh)"' ;;
      bash) add_line_if_missing "$HOME/.bashrc" 'starship init bash' 'eval "$(starship init bash)"' ;;
      fish) add_line_if_missing "$HOME/.config/fish/config.fish" 'starship init fish' 'starship init fish | source' ;;
    esac
    info "Starship added — shows git branch/status in your prompt automatically once you reload your shell"
  fi

  echo "== Validating Ghostty config =="
  [ -f "$GHOSTTY_CONF" ] && info "Config file present at $GHOSTTY_CONF" || fail "Config file missing"
  info "Config contents:"
  cat "$GHOSTTY_CONF"
}

# =====================================================================
# INSTALL — TMUX SHORTCUT TRAINER (optional)
# =====================================================================
install_tmux() {
  install_pkg "tmux"

  # ---- Customization prompts ----
  local PREFIX_KEY="C-b"       # tmux syntax
  local PREFIX_DISPLAY="Ctrl-B" # human-readable, used in tip strings
  local SPLIT_V='%'             # default vertical-split key
  local SPLIT_H='"'             # default horizontal-split key
  local SPLIT_V_DISPLAY='%'
  local SPLIT_H_DISPLAY='"'
  local VIM_NAV="no"

  if ask_yes_no "Customize tmux keybindings? (default: standard tmux keys)"; then
    echo "Prefix key:"
    echo "  1) Ctrl-B  (tmux default, matches every tutorial)"
    echo "  2) Ctrl-A  (screen-style; conflicts with shell beginning-of-line)"
    echo "  3) Ctrl-Space  (no shell conflict, easy to press)"
    read -r -p "Choice [1-3, default 1]: " prefix_choice
    case "$prefix_choice" in
      2) PREFIX_KEY="C-a"; PREFIX_DISPLAY="Ctrl-A" ;;
      3) PREFIX_KEY="C-Space"; PREFIX_DISPLAY="Ctrl-Space" ;;
      *) ;;
    esac

    echo "Split keys:"
    echo "  1) %  vertical, \"  horizontal  (tmux default)"
    echo "  2) |  vertical, -  horizontal  (mnemonic)"
    read -r -p "Choice [1-2, default 1]: " split_choice
    if [ "$split_choice" = "2" ]; then
      SPLIT_V='|'; SPLIT_H='-'
      SPLIT_V_DISPLAY='|'; SPLIT_H_DISPLAY='-'
    fi

    if ask_yes_no "Enable vim-style pane navigation (prefix then h/j/k/l)?"; then
      VIM_NAV="yes"
    fi
  fi

  # ---- Generate ~/.config/i-shell/tmux-tip.sh ----
  local TIP_DIR="$HOME/.config/i-shell"
  local TIP_SCRIPT="$TIP_DIR/tmux-tip.sh"
  mkdir -p "$TIP_DIR"

  {
    echo "#!/usr/bin/env bash"
    echo "# generated by i-shell.sh — rotates tmux shortcut hints in the status bar"
    echo "tips=("
    printf '  "[%s %s]  split pane vertically"\n' "$PREFIX_DISPLAY" "$SPLIT_V_DISPLAY"
    printf '  "[%s %s]  split pane horizontally"\n' "$PREFIX_DISPLAY" "$SPLIT_H_DISPLAY"
    printf '  "[%s arrows]  move between panes"\n' "$PREFIX_DISPLAY"
    [ "$VIM_NAV" = "yes" ] && printf '  "[%s h/j/k/l]  vim-style pane navigation"\n' "$PREFIX_DISPLAY"
    printf '  "[%s x]  close current pane"\n' "$PREFIX_DISPLAY"
    printf '  "[%s z]  zoom pane to fullscreen (toggle)"\n' "$PREFIX_DISPLAY"
    printf '  "[%s c]  create new window"\n' "$PREFIX_DISPLAY"
    printf '  "[%s n / p]  next / previous window"\n' "$PREFIX_DISPLAY"
    printf '  "[%s ,]  rename current window"\n' "$PREFIX_DISPLAY"
    printf '  "[%s d]  detach (session keeps running)"\n' "$PREFIX_DISPLAY"
    printf '  "[%s ?]  show all keybindings"\n' "$PREFIX_DISPLAY"
    echo ")"
    echo 'idx=$(( ($(date +%s) / 10) % ${#tips[@]} ))'
    echo 'printf "Tip: %s" "${tips[$idx]}"'
  } > "$TIP_SCRIPT"
  chmod +x "$TIP_SCRIPT"
  info "Wrote $TIP_SCRIPT"

  # ---- Generate ~/.tmux.conf ----
  local TMUX_CONF="$HOME/.tmux.conf"
  if [ -f "$TMUX_CONF" ] && ! grep -q "generated by i-shell.sh" "$TMUX_CONF"; then
    cp "$TMUX_CONF" "$TMUX_CONF.i-shell-bak.$(date +%s)"
    info "Backed up existing ~/.tmux.conf to $(basename "$TMUX_CONF").i-shell-bak.*"
  fi

  {
    echo "# ~/.tmux.conf — generated by i-shell.sh"
    echo "# Feel free to edit; re-running install regenerates this file (backup made first)."
    echo ""
    echo "# --- Prefix ---"
    echo "unbind C-b"
    echo "set -g prefix $PREFIX_KEY"
    echo "bind $PREFIX_KEY send-prefix"
    echo ""
    echo "# --- Quality of life ---"
    echo "set -g mouse on"
    echo "set -g base-index 1"
    echo "setw -g pane-base-index 1"
    echo "set -g renumber-windows on"
    echo "set -g history-limit 50000"
    echo "set -g escape-time 10"
    echo ""
    if [ "$SPLIT_V" != '%' ]; then
      echo "# --- Splits (mnemonic keys) ---"
      echo "unbind '\"'"
      echo "unbind %"
      echo "bind $SPLIT_V split-window -h -c \"#{pane_current_path}\""
      echo "bind $SPLIT_H split-window -v -c \"#{pane_current_path}\""
      echo ""
    fi
    if [ "$VIM_NAV" = "yes" ]; then
      echo "# --- Vim-style pane navigation ---"
      echo "bind h select-pane -L"
      echo "bind j select-pane -D"
      echo "bind k select-pane -U"
      echo "bind l select-pane -R"
      echo ""
    fi
    echo "# --- Reload ---"
    echo "bind r source-file ~/.tmux.conf \\; display 'reloaded'"
    echo ""
    echo "# --- Status bar (minimal, right-aligned rotating tip) ---"
    echo "set -g status-interval 10"
    echo "set -g status-position bottom"
    echo "set -g status-style 'bg=colour235,fg=colour250'"
    echo "set -g status-left ''"
    echo "set -g status-left-length 0"
    echo "set -g status-right-length 200"
    echo "set -g status-right '#[fg=yellow]#(bash $TIP_SCRIPT 2>/dev/null)'"
    echo "setw -g window-status-format ''"
    echo "setw -g window-status-current-format ''"
    echo "set -g status-justify left"
  } > "$TMUX_CONF"
  info "Wrote $TMUX_CONF (prefix=$PREFIX_DISPLAY, splits=$SPLIT_V_DISPLAY/$SPLIT_H_DISPLAY, vim-nav=$VIM_NAV)"

  # ---- Auto-start scope ----
  echo ""
  echo "Auto-start tmux when opening a terminal?"
  echo "  1) Everywhere (Ghostty, iTerm, Terminal.app, VS Code, SSH)"
  echo "  2) Only in Ghostty"
  echo "  3) Don't auto-start (I'll type 'tmux' myself)"
  read -r -p "Choice [1-3, default 3]: " autostart_choice

  case "$autostart_choice" in
    1|2)
      local GUARD=""
      [ "$autostart_choice" = "2" ] && GUARD='ghostty'
      write_tmux_autostart "$GUARD"
      ;;
    *) info "Skipping auto-start. Type 'tmux' to start a session." ;;
  esac
}

# Adds the tmux auto-start one-liner to the current TARGET_SHELL's rc file.
# $1 = "" for everywhere, "ghostty" for Ghostty-only.
write_tmux_autostart() {
  local scope="$1"
  case "$TARGET_SHELL" in
    zsh|bash)
      local RC
      [ "$TARGET_SHELL" = "zsh" ] && RC="$HOME/.zshrc" || RC="$HOME/.bashrc"
      local GUARD='[ -z "$TMUX" ] && [[ $- == *i* ]] && command -v tmux >/dev/null 2>&1'
      [ "$scope" = "ghostty" ] && GUARD="$GUARD"' && [ -n "$GHOSTTY_RESOURCES_DIR" ]'
      add_line_if_missing "$RC" "i-shell tmux auto-start" "
# --- i-shell tmux auto-start ---
$GUARD && { tmux attach -t main 2>/dev/null || exec tmux new-session -s main; }"
      ;;
    fish)
      local RC="$HOME/.config/fish/config.fish"
      local COND='status is-interactive; and not set -q TMUX; and type -q tmux'
      [ "$scope" = "ghostty" ] && COND="$COND"'; and test -n "$GHOSTTY_RESOURCES_DIR"'
      add_line_if_missing "$RC" "i-shell tmux auto-start" "
# --- i-shell tmux auto-start ---
$COND; and begin; tmux attach -t main 2>/dev/null; or exec tmux new-session -s main; end"
      ;;
  esac
  info "tmux auto-start enabled (${scope:-everywhere})"
}

# =====================================================================
# UNINSTALL — ZSH / BASH / FISH
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
  strip_from_rc "$ZSHRC" 'i-shell tmux auto-start'
  strip_from_rc "$ZSHRC" 'tmux attach -t main'
  strip_from_rc "$ZSHRC" 'i-shell fzf key-bindings'
  strip_from_rc "$ZSHRC" '^for f in /usr/share/'
  strip_from_rc "$ZSHRC" '^         /usr/share/'
  strip_from_rc "$ZSHRC" '^  \[ -f "\$f" \] && source "\$f"$'
  strip_from_rc "$ZSHRC" '^done$'

  if [ "$PKG_MGR" != "none" ] && ask_yes_no "Uninstall zsh plugin packages (zsh-autosuggestions, zsh-syntax-highlighting, zsh-completions, fzf)?"; then
    for pkg in zsh-autosuggestions zsh-syntax-highlighting zsh-completions fzf; do
      uninstall_pkg "$pkg"
    done
  fi

  local ZSH_PLUGIN_DIR="$HOME/.local/share/zsh-plugins"
  if [ -d "$ZSH_PLUGIN_DIR" ] && ask_yes_no "Delete git-cloned zsh plugins at $ZSH_PLUGIN_DIR?"; then
    rm -rf "$ZSH_PLUGIN_DIR"
    info "Removed $ZSH_PLUGIN_DIR"
  fi
}

uninstall_bash() {
  local BASHRC="$HOME/.bashrc"

  echo "== Cleaning ~/.bashrc =="
  strip_from_rc "$BASHRC" 'blesh/ble\.sh'
  strip_from_rc "$BASHRC" 'ble-attach'
  strip_from_rc "$BASHRC" 'bash_completion\.sh'
  strip_from_rc "$BASHRC" 'key-bindings\.bash'
  strip_from_rc "$BASHRC" 'starship init bash'
  strip_from_rc "$BASHRC" 'i-shell tmux auto-start'
  strip_from_rc "$BASHRC" 'tmux attach -t main'
  strip_from_rc "$BASHRC" 'i-shell fzf key-bindings'
  strip_from_rc "$BASHRC" '^for f in /usr/share/'
  strip_from_rc "$BASHRC" '^         /usr/share/'
  strip_from_rc "$BASHRC" '^  \[ -f "\$f" \] && source "\$f"$'
  strip_from_rc "$BASHRC" '^done$'

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

uninstall_fish() {
  local FISH_CONF="$HOME/.config/fish/config.fish"

  echo "== Cleaning config.fish =="
  strip_from_rc "$FISH_CONF" 'fzf_key_bindings'
  strip_from_rc "$FISH_CONF" 'key-bindings\.fish'
  strip_from_rc "$FISH_CONF" 'starship init fish'
  strip_from_rc "$FISH_CONF" 'i-shell tmux auto-start'
  strip_from_rc "$FISH_CONF" 'tmux attach -t main'

  if [ "$PKG_MGR" != "none" ] && ask_yes_no "Uninstall fzf?"; then
    uninstall_pkg "fzf"
  fi
  if [ "$PKG_MGR" != "none" ] && ask_yes_no "Uninstall the fish shell itself?"; then
    uninstall_pkg "fish"
  fi
}

uninstall_ghostty() {
  local GHOSTTY_DIR="$HOME/.config/ghostty"
  local GHOSTTY_CONF="$GHOSTTY_DIR/config"

  if [ -f "$GHOSTTY_CONF" ]; then
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
    case "$PKG_MGR" in
      brew)
        brew uninstall --cask ghostty 2>/dev/null || warn "brew uninstall failed - remove Ghostty manually if it was installed another way."
        ;;
      apt)
        if dpkg -s ghostty >/dev/null 2>&1; then
          sudo apt remove -y ghostty || warn "apt remove failed"
        else
          warn "Ghostty wasn't installed via apt - remove it manually."
        fi
        ;;
      dnf)
        sudo dnf remove -y ghostty || warn "dnf remove failed"
        ask_yes_no "Also disable the pgdev/ghostty COPR?" && sudo dnf copr disable -y pgdev/ghostty
        ;;
      pacman)
        sudo pacman -Rs --noconfirm ghostty || warn "pacman remove failed - if installed via AUR, use your AUR helper"
        ;;
      zypper)
        warn "Ghostty wasn't installed via zypper - remove it manually."
        ;;
      *)
        warn "Unknown package manager - remove Ghostty manually."
        ;;
    esac
  fi
}

uninstall_tmux() {
  local TIP_SCRIPT="$HOME/.config/i-shell/tmux-tip.sh"
  local TMUX_CONF="$HOME/.tmux.conf"

  if [ -f "$TMUX_CONF" ] && grep -q "generated by i-shell.sh" "$TMUX_CONF" 2>/dev/null; then
    local LATEST_BAK
    LATEST_BAK=$(ls -t "$TMUX_CONF".i-shell-bak.* 2>/dev/null | head -n1 || true)
    if [ -n "$LATEST_BAK" ] && ask_yes_no "Restore ~/.tmux.conf from backup $(basename "$LATEST_BAK")?"; then
      mv "$LATEST_BAK" "$TMUX_CONF"
      info "Restored $TMUX_CONF from backup"
    elif ask_yes_no "Delete ~/.tmux.conf (generated by i-shell)?"; then
      rm -f "$TMUX_CONF"
      info "Removed $TMUX_CONF"
    fi
  fi

  if [ -f "$TIP_SCRIPT" ] && ask_yes_no "Delete tip-rotation script $TIP_SCRIPT?"; then
    rm -f "$TIP_SCRIPT"
    info "Removed $TIP_SCRIPT"
    rmdir "$HOME/.config/i-shell" 2>/dev/null || true
  fi

  if [ "$PKG_MGR" != "none" ] && pkg_installed "tmux" && ask_yes_no "Uninstall the tmux package itself?"; then
    uninstall_pkg "tmux"
  fi
}

uninstall_starship() {
  command -v starship >/dev/null 2>&1 || return 0
  ask_yes_no "Uninstall Starship prompt?" || return 0
  if [ "$PKG_MGR" = "brew" ] && brew list starship >/dev/null 2>&1; then
    brew uninstall starship
  elif [ "$PKG_MGR" = "apt" ] && dpkg -s starship >/dev/null 2>&1; then
    sudo apt remove -y starship
  else
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

# =====================================================================
# DISPATCH
# =====================================================================
if [ "$ACTION" = "install" ]; then
  echo ""
  if ask_yes_no "Would you like to install Ghostty (GPU-accelerated terminal)?"; then
    install_ghostty
    if ask_yes_no "Customize Ghostty's visuals now (theme, font, git-aware prompt)?"; then
      configure_ghostty
    fi
  fi

  echo ""
  if ask_yes_no "Enable tmux shortcut trainer mode? (installs tmux + always-visible rotating shortcut hint bar)"; then
    install_tmux
  fi

  case "$TARGET_SHELL" in
    zsh)  install_zsh ;;
    bash) install_bash ;;
    fish) install_fish ;;
  esac

else  # uninstall
  echo ""
  warn "This will remove I-Shell's changes from your shell config."
  warn "A timestamped backup of each rc file will be saved as <rcfile>.i-shell-bak.<epoch>."
  ask_yes_no "Continue?" || { info "Aborted."; exit 0; }

  case "$TARGET_SHELL" in
    zsh)  uninstall_zsh ;;
    bash) uninstall_bash ;;
    fish) uninstall_fish ;;
  esac

  echo ""
  if [ -f "$HOME/.tmux.conf" ] || [ -f "$HOME/.config/i-shell/tmux-tip.sh" ] || pkg_installed "tmux"; then
    if ask_yes_no "Remove tmux trainer mode (config, tip script, and optionally tmux itself)?"; then
      uninstall_tmux
    fi
  fi

  echo ""
  uninstall_starship
  echo ""
  if ask_yes_no "Also remove Ghostty and its config?"; then
    uninstall_ghostty
  fi

  echo ""
  info "Done. Open a new terminal to load a clean shell environment."
fi
