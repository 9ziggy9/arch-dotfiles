#!/usr/bin/env bash
# bootstrap.sh: install everything these dotfiles need on Arch, then stow them.
#
#   ./bootstrap.sh            install packages and tinty, then stow
#   ./bootstrap.sh --no-stow  install only
#
# Safe to run again: installed packages are skipped (--needed), and tinty
# and paru are only installed when missing. Stowing stops on any file in
# ~ that would be overwritten, so nothing of yours is replaced.

set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
stow=yes
[ "${1:-}" = --no-stow ] && stow=no

step() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }

[ "$(id -u)" -ne 0 ] || { echo "Run as your user, not root (sudo is used where needed)." >&2; exit 1; }
command -v pacman >/dev/null || { echo "This is for Arch Linux (no pacman found)." >&2; exit 1; }

# ------------------------------------------------------------ official repos

pacman_pkgs=(
    # X11 and i3
    xorg-server xorg-xinit xorg-xmodmap xorg-setxkbmap xorg-xprop
    i3-wm i3lock xss-lock dex network-manager-applet
    picom rofi flameshot libnotify
    # audio: pactl for the volume keys
    pipewire-pulse libpulse
    # status bar: bumblebee-status modules and statusline.py
    python python-gobject python-cairo pango python-psutil python-netifaces iw
    # terminal and shell (nvim + xclip: kitty's scrollback pager)
    # (fzf: .zshrc loads its keys and completion with fzf --zsh)
    kitty neovim xclip zsh keychain openssh fzf
    # browser
    qutebrowser
    # Boox mirroring (boox-screen)
    scrcpy android-tools
    # emacs: magit/forge, gh, clangd, ripgrep, tree-sitter grammar builds
    emacs git github-cli clang ripgrep tree-sitter base-devel
    # pdf-tools' epdfinfo, and TeX Live for the LaTeX/org preview
    poppler-glib libpng zlib
    texlive-basic texlive-latex texlive-latexrecommended texlive-latexextra
    texlive-fontsrecommended texlive-mathscience texlive-binextra
    texlive-plaingeneric
    # the default font everywhere (font-select lists any other monospace font)
    ttf-meslo-nerd
    # deploying, and cargo for tinty
    stow rustup
)

aur_pkgs=(
    bumblebee-status          # the bar
    tdrop                     # dropdown terminal ($mod+d)
    zsh-theme-powerlevel10k   # prompt, sourced from /usr/share by .zshrc
    vesktop-bin               # Discord, themed by apply-scheme
)

step "Official packages"
sudo pacman -Syu --needed "${pacman_pkgs[@]}"

# ------------------------------------------------------------ AUR

if ! command -v paru >/dev/null; then
    step "paru (AUR helper)"
    build="$(mktemp -d)"
    git clone --depth 1 https://aur.archlinux.org/paru-bin.git "$build/paru-bin"
    (cd "$build/paru-bin" && makepkg -si --noconfirm)
    rm -rf "$build"
fi

step "AUR packages"
paru -S --needed "${aur_pkgs[@]}"

# ------------------------------------------------------------ outside pacman

step "Rust toolchain"
rustup toolchain list | grep -q . || rustup default stable

step "tinty (color schemes; theme-select and font-select)"
export PATH="$HOME/.cargo/bin:$PATH"
if command -v tinty >/dev/null; then
    echo "already installed: $(command -v tinty)"
else
    cargo install --locked tinty
fi

# ------------------------------------------------------------ stow

if [ "$stow" = yes ]; then
    step "Stowing dotfiles into ~"
    cd "$here"
    packages=()
    for d in */; do packages+=("${d%/}"); done
    # dry run first: if anything in ~ is in the way, list it and stop
    if ! stow -n --ignore=__pycache__ "${packages[@]}" 2>"${TMPDIR:-/tmp}/bootstrap-stow.$$"; then
        cat "${TMPDIR:-/tmp}/bootstrap-stow.$$" >&2
        rm -f "${TMPDIR:-/tmp}/bootstrap-stow.$$"
        echo "Move or delete the files above, then run: cd $here && stow --ignore=__pycache__ ${packages[*]}" >&2
        exit 1
    fi
    rm -f "${TMPDIR:-/tmp}/bootstrap-stow.$$"
    stow --ignore=__pycache__ "${packages[@]}"
    echo "stowed: ${packages[*]}"
fi

# ------------------------------------------------------------ by hand

step "Done. Left to do by hand:"
cat <<'EOF'
  - Shell: chsh -s /usr/bin/zsh
  - NetworkManager, if you use it: sudo systemctl enable --now NetworkManager
  - Start X with startx; i3 applies the default color scheme on first start
  - Emacs downloads its packages on first launch; when a PDF first opens,
    let pdf-tools build epdfinfo
  - forge: a GitHub token in ~/.authinfo; gh: gh auth login
  - Boox over Wi-Fi: plug it in, then boox-screen --wifi
  - Vesktop (Discord), once: Settings > Themes, tick base16-tinty.css;
    Settings > Plugins, turn on KeepCurrentChannel
EOF
