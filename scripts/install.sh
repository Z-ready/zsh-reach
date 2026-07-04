#!/usr/bin/env sh
set -eu

REACH_REPO="${REACH_REPO:-Z-ready/reach}"
REACH_VERSION="${REACH_VERSION:-latest}"
REACH_PREFIX="${REACH_PREFIX:-$HOME/.local}"
BIN_DIR="$REACH_PREFIX/bin"
SHARE_DIR="$REACH_PREFIX/share/reach"

detect_target() {
  os="$(uname -s | tr '[:upper:]' '[:lower:]')"
  arch="$(uname -m)"

  case "$os" in
    darwin) os="macos" ;;
    linux) os="linux" ;;
    msys*|mingw*|cygwin*) os="windows" ;;
    *) echo "reach: unsupported OS: $os" >&2; exit 1 ;;
  esac

  case "$arch" in
    arm64|aarch64) arch="aarch64" ;;
    x86_64|amd64) arch="x86_64" ;;
    *) echo "reach: unsupported architecture: $arch" >&2; exit 1 ;;
  esac

  printf '%s-%s' "$os" "$arch"
}

release_base_url() {
  if [ "$REACH_VERSION" = "latest" ]; then
    printf 'https://github.com/%s/releases/latest/download' "$REACH_REPO"
  else
    printf 'https://github.com/%s/releases/download/%s' "$REACH_REPO" "$REACH_VERSION"
  fi
}

download() {
  url="$1"
  output="$2"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$url" -o "$output"
  elif command -v wget >/dev/null 2>&1; then
    wget -qO "$output" "$url"
  else
    echo "reach: install requires curl or wget" >&2
    exit 1
  fi
}

target="$(detect_target)"
base_url="$(release_base_url)"
archive="${TMPDIR:-/tmp}/reach-${target}.tar.gz"
workdir="${TMPDIR:-/tmp}/reach-install.$$"

rm -rf "$workdir"
mkdir -p "$workdir" "$BIN_DIR" "$SHARE_DIR"
download "$base_url/reach-${target}.tar.gz" "$archive"
tar -xzf "$archive" -C "$workdir"

install -m 755 "$workdir/reach" "$BIN_DIR/reach"
install -m 755 "$workdir/reach-helper" "$BIN_DIR/reach-helper"
install -m 644 "$workdir/to.plugin.zsh" "$SHARE_DIR/to.plugin.zsh"
if [ -f "$workdir/_gt" ]; then
  mkdir -p "$REACH_PREFIX/share/zsh/site-functions"
  install -m 644 "$workdir/_gt" "$REACH_PREFIX/share/zsh/site-functions/_gt"
fi

rm -rf "$workdir" "$archive"

cat <<EOF
reach installed to $REACH_PREFIX

Add this to ~/.zshrc:
  eval "\$(reach init zsh)"

Then reload your shell and jump with:
  gt <query>
EOF
