class To < Formula
  desc "Exploratory zsh directory jumper"
  homepage "https://github.com/Z-ready/zsh-to"
  url "https://github.com/Z-ready/zsh-to/archive/refs/tags/v1.0.3.tar.gz"
  sha256 "5197f26dfb3bec06dc1e93a8604e4eee98e02c4d1fa88dd8d96b7cc96997dc14"
  version "1.0.3"
  license "MIT"

  depends_on "fd" => :recommended
  depends_on "fzf" => :optional

  def install
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
    system "zsh", "-n", "#{pkgshare}/to.plugin.zsh"
    assert_match "to config:", shell_output("zsh -fc 'source #{pkgshare}/to.plugin.zsh; to --doctor'")
  end
end
