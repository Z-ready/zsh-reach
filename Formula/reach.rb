class Reach < Formula
  desc "Fast zsh directory and object jumper"
  homepage "https://github.com/Z-ready/zsh-to"
  url "https://github.com/Z-ready/zsh-to/archive/refs/tags/v1.6.0.tar.gz"
  sha256 "TODO"
  license "MIT"

  depends_on "rust" => :build
  depends_on "zsh"

  def install
    system "cargo", "install", *std_cargo_args
    bin.install "bin/reach"
    pkgshare.install "to.plugin.zsh"
    zsh_completion.install "completions/_gt"
    doc.install "README.md"
    prefix.install "LICENSE"
  end

  def caveats
    <<~EOS
      Add this to your ~/.zshrc:

        eval "$(reach init zsh)"

      Then reload zsh and jump with:

        gt backend

      Existing users who prefer the old command can add:

        alias to=gt
    EOS
  end

  test do
    assert_path_exists bin/"reach"
    assert_path_exists bin/"reach-helper"
    assert_match "source #{pkgshare}/to.plugin.zsh", shell_output("#{bin}/reach init zsh")
    system "zsh", "-n", "#{pkgshare}/to.plugin.zsh"
    assert_match "reach", shell_output("zsh -fc 'source #{pkgshare}/to.plugin.zsh; gt --version'")
  end
end
