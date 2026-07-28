#!/usr/bin/env bash
#
# setup-i-shell.sh  (I-Shell = Intelligent Shell)
#
# Sets up autosuggestions + syntax highlighting + fuzzy search + completions
# for zsh, bash, or fish — on macOS (Homebrew) or Linux (apt).
#
# Usage:
#   ./setup-i-shell.sh            # auto-detects your current shell
#   ./setup-i-shell.sh zsh        # force a specific shell
#   ./setup-i-shell.sh bash
#   ./setup-i-shell.sh fish
#
# Safe to re-run: checks before installing/appending anything.

set -e

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[0;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[OK]${NC} $1"; }
warn()  { echo -e "${YELLOW}[..]${NC} $1"; }
fail()  { echo -e "${RED}[FAIL]${NC} $1"; exit 1; }

# ---------- Step 0: figure out target shell ----------
TARGET_SHELL="$1"
if [ -z "$TARGET_SHELL" ]; then
  TARGET_SHELL="$(basename "$SHELL")"
  warn "No shell specified, detected default shell: $TARGET_SHELL"
fi

case "$TARGET_SHELL" in
  zsh|bash|fish) info "Target shell: $TARGET_SHELL" ;;
  *) fail "Unsupported shell '$TARGET_SHELL'. Use zsh, bash, or fish." ;;
esac

# ---------- Step 0b: figure out package manager ----------
if command -v brew >/dev/null 2>&1; then
  PKG_MGR="brew"
  PKG_INSTALL="brew install"
  PKG_PREFIX="$(brew --prefix)"
elif command -v apt >/dev/null 2>&1; then
  PKG_MGR="apt"
  PKG_INSTALL="sudo apt install -y"
  PKG_PREFIX="/usr"
else
  fail "Neither Homebrew nor apt found. This script supports macOS (brew) and Debian/Ubuntu/Kali (apt) only."
fi
info "Package manager: $PKG_MGR"

install_pkg() {
  local pkg="$1"
  if [ "$PKG_MGR" = "brew" ]; then
    brew list "$pkg" >/dev/null 2>&1 && { info "$pkg already installed"; return; }
  else
    dpkg -s "$pkg" >/dev/null 2>&1 && { info "$pkg already installed"; return; }
  fi
  warn "Installing $pkg..."
  $PKG_INSTALL "$pkg" || fail "Failed to install $pkg"
  info "$pkg installed"
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

# =====================================================================
# ZSH
# =====================================================================
setup_zsh() {
  local ZSHRC="$HOME/.zshrc"
  touch "$ZSHRC"

  if [ "$PKG_MGR" = "brew" ]; then
    for pkg in zsh-autosuggestions zsh-syntax-highlighting fzf zsh-completions; do
      install_pkg "$pkg"
    done
    local SUGGEST="$PKG_PREFIX/share/zsh-autosuggestions/zsh-autosuggestions.zsh"
    local HIGHLIGHT="$PKG_PREFIX/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
    local COMP_DIR="$PKG_PREFIX/share/zsh-completions"
  else
    for pkg in zsh-autosuggestions zsh-syntax-highlighting fzf; do
      install_pkg "$pkg"
    done
    local SUGGEST="/usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh"
    local HIGHLIGHT="/usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
    local COMP_DIR=""  # Debian ships zsh completions in the default fpath already
  fi

  echo "== fzf key bindings =="
  if [ -f "$HOME/.fzf.zsh" ]; then
    info "fzf shell integration already set up"
  elif [ -d "$PKG_PREFIX/opt/fzf" ]; then
    warn "Running fzf install script (answer its prompts with 'y')..."
    "$PKG_PREFIX/opt/fzf/install"
  else
    warn "Add fzf's shell integration manually: see https://github.com/junegunn/fzf#setting-up-shell-integration"
  fi

  echo "== Updating ~/.zshrc =="
  if [ -n "$COMP_DIR" ]; then
    add_line_if_missing "$ZSHRC" "zsh-completions" "
# --- completions ---
FPATH=$COMP_DIR:\$FPATH
autoload -Uz compinit
compinit"
  fi
  add_line_if_missing "$ZSHRC" "zsh-autosuggestions.zsh" "
# --- autosuggestions ---
source $SUGGEST"
  add_line_if_missing "$ZSHRC" "zsh-syntax-highlighting.zsh" "
# --- syntax highlighting (must stay last) ---
source $HIGHLIGHT"

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
  [ -f "$SUGGEST" ] && info "autosuggestions file present" || fail "autosuggestions file missing at $SUGGEST"
  [ -f "$HIGHLIGHT" ] && info "syntax-highlighting file present" || fail "syntax-highlighting file missing at $HIGHLIGHT"
  grep -qF "zsh-autosuggestions" "$ZSHRC" && info "autosuggestions referenced in .zshrc"
  grep -qF "zsh-syntax-highlighting" "$ZSHRC" && info "syntax-highlighting referenced in .zshrc"

  echo -e "${GREEN}zsh setup complete.${NC} Reloading..."
  exec zsh -l
}

# =====================================================================
# BASH
# =====================================================================
setup_bash() {
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
    warn "fzf's Debian package auto-wires /usr/share/doc/fzf/examples/key-bindings.bash — add it manually if missing:"
    add_line_if_missing "$BASHRC" "key-bindings.bash" '[ -f /usr/share/doc/fzf/examples/key-bindings.bash ] && source /usr/share/doc/fzf/examples/key-bindings.bash'
  fi

  echo "== Installing ble.sh (autosuggestions + syntax highlighting for bash) =="
  # bash has no equivalent to zsh-autosuggestions as a simple package;
  # ble.sh (Bash Line Editor) is the standard tool that provides both.
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
  # ble.sh must be sourced near the TOP of .bashrc (before other init)
  if ! grep -qF "blesh/ble.sh" "$BASHRC"; then
    # prepend rather than append
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

  echo -e "${GREEN}bash setup complete.${NC} Reloading..."
  exec bash -l
}

# =====================================================================
# FISH
# =====================================================================
setup_fish() {
  install_pkg "fish"
  install_pkg "fzf"

  local FISH_CONF_DIR="$HOME/.config/fish"
  mkdir -p "$FISH_CONF_DIR"
  local FISH_CONF="$FISH_CONF_DIR/config.fish"
  touch "$FISH_CONF"

  info "fish has autosuggestions and syntax highlighting built in — no plugins needed"

  echo "== Adding fzf key bindings for fish =="
  local FZF_FISH_BINDINGS="$PKG_PREFIX/opt/fzf/shell/key-bindings.fish"
  if [ -f "$FZF_FISH_BINDINGS" ]; then
    add_line_if_missing "$FISH_CONF" "fzf_key_bindings" "source $FZF_FISH_BINDINGS
fzf_key_bindings"
  else
    warn "fzf fish bindings file not found at expected path — check https://github.com/junegunn/fzf#fish"
  fi

  echo "== Validating =="
  command -v fish >/dev/null 2>&1 && info "fish installed" || fail "fish not found after install"

  echo -e "${GREEN}fish setup complete.${NC}"
  warn "To make fish your default shell: chsh -s \$(which fish)"
  echo "Launching a fish session now..."
  exec fish
}

# =====================================================================
# GHOSTTY (optional)
# =====================================================================
ask_yes_no() {
  local prompt="$1" answer
  read -r -p "$prompt [y/N]: " answer
  [[ "$answer" =~ ^[Yy]$ ]]
}

install_ghostty() {
  if command -v ghostty >/dev/null 2>&1; then
    info "Ghostty already installed"
    return
  fi

  if [ "$PKG_MGR" = "brew" ]; then
    warn "Installing Ghostty via Homebrew cask..."
    brew install --cask ghostty || fail "Ghostty install failed"
  else
    # Debian/Ubuntu/Kali: try apt first (native package only on Ubuntu 26.04+),
    # fall back to the community-maintained installer if apt doesn't have it.
    if apt list --installable 2>/dev/null | grep -q '^ghostty/'; then
      warn "Installing Ghostty via apt..."
      sudo apt install -y ghostty || fail "Ghostty install failed"
    else
      warn "Ghostty isn't in this distro's apt repos yet — using the community .deb installer (mkasberg/ghostty-ubuntu)..."
      /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/mkasberg/ghostty-ubuntu/HEAD/install.sh)" \
        || fail "Ghostty community installer failed. See https://github.com/mkasberg/ghostty-ubuntu for manual steps."
    fi
  fi

  command -v ghostty >/dev/null 2>&1 && info "Ghostty installed" || warn "Ghostty command not found on PATH yet — you may need to open a new terminal"
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
    install_pkg "starship" 2>/dev/null || { warn "Installing starship via its official script..."; curl -sS https://starship.rs/install.sh | sh -s -- -y || fail "starship install failed"; }
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

echo ""
if ask_yes_no "Would you like to install Ghostty (GPU-accelerated terminal)?"; then
  install_ghostty
  if ask_yes_no "Customize Ghostty's visuals now (theme, font, git-aware prompt)?"; then
    configure_ghostty
  fi
fi

# ---------- dispatch ----------
case "$TARGET_SHELL" in
  zsh)  setup_zsh ;;
  bash) setup_bash ;;
  fish) setup_fish ;;
esac
