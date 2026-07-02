class To < Formula
  desc "Exploratory zsh directory jumper"
  homepage "https://github.com/Z-ready/zsh-to"
  url "https://github.com/Z-ready/zsh-to/archive/refs/tags/v1.1.0.tar.gz"
  sha256 "674b2b0883e6e2e7fef28844425ebba9eed37baca3110a52e6cde50e22b0199d"
  version "1.1.0"
  license "MIT"

  depends_on "rust" => :build
  depends_on "fd"
  depends_on "fzf"
  depends_on "sqlite"

  on_macos do
    depends_on "fswatch"
  end

  on_linux do
    depends_on "inotify-tools"
  end

  def install
    system "cargo", "install", *std_cargo_args
    pkgshare.install "to.plugin.zsh"
    zsh_completion.install "completions/_to"
    doc.install "README.md"
    prefix.install "LICENSE"
  end

  def caveats
    <<~EOS
      Add this to your ~/.zshrc:

        source "#{opt_pkgshare}/to.plugin.zsh"

      Then reload zsh and configure search roots:

        source ~/.zshrc
        to use ~/Projects
        to roots
    EOS
  end

  test do
    assert_path_exists bin/"to-helper"
    system "zsh", "-n", "#{pkgshare}/to.plugin.zsh"
    assert_match "to config:", shell_output("zsh -fc 'source #{pkgshare}/to.plugin.zsh; to --doctor'")
  end
end
