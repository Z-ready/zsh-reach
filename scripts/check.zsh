#!/usr/bin/env zsh

set -e
set -u
set -o pipefail

run() {
  print -r -- "+ $*"
  "$@"
}

run zsh -n to.plugin.zsh
run zsh -n reach.plugin.zsh
run zsh -n bin/reach
run zsh -n bin/to
run zsh -n tests/run.zsh
run zsh -n completions/_gt
run zsh -n completions/_to
run ruby -c Formula/reach.rb
run ruby -c Formula/to.rb

run cargo fmt -- --check
run cargo test
run cargo clippy --all-targets -- -D warnings
run cargo build --release

run zsh tests/run.zsh
