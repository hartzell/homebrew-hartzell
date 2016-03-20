class TidyMarkdown < Formula
  desc "Beautify Markdown"
  homepage "https://www.npmjs.com/package/tidy-markdown"
  url "https://github.com/slang800/tidy-markdown/archive/v1.0.0.tar.gz"
  sha256 "e1f107fd3228ecede16d89b896389f2dab1681350bbc464d2aa1e602eddd1f84"

  depends_on "node"

  def install
    ENV.prepend_path "PATH", "#{Formula["node"].opt_libexec}/npm/bin"
    system "npm", "install"
    libexec.install Dir["*"]
    bin.install_symlink "#{libexec}/bin/index.js" => "tidy-markdown"
  end

  test do
    (testpath/"test.md").write <<-EOS.undent
      #    Now is the time

      header1 | header 2 | long header number 3
      ---|---|---
      foo|bar mitzvah| baz
      eenie|meenie|myne-mo

    EOS
    cmd = ["cat", testpath/"test.md", "|", bin/"tidy-markdown"].join(' ')
    s = pipe_output(cmd)
    # check if it cleaned up the extra whitespace after the h1
    assert_match /# Now is the time/, s
  end
end
