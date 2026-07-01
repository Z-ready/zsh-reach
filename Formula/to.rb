class To < Formula
  desc "Exploratory zsh directory jumper"
  homepage "https://github.com/Z-ready/zsh-to"
  url "https://github.com/Z-ready/zsh-to/archive/refs/tags/v1.0.1.tar.gz"
  sha256 "016c2b8b05eb98a1574c1c98bf24c6d3d45064fce4817cd777d9ef6785a1b196"
  version "1.0.1"
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
