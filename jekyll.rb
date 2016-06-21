#
# TODO:
#   - Get feedback.
#   - The recipe from which I stole this (cocoapods.rb)
#     didn't have to hardcode the version into install line:
#     `system "gem", "install", "cocoapods-#{version}.gem"`
#     I think that's because they used 'url' where I used 'head'
#   - The test could be mo' better.
#
class Jekyll < Formula
  desc "Jekyll is a blog-aware, static site generator in Ruby"
  homepage "https://jekyllrb.com"
  head 'https://github.com/jekyll/jekyll.git', :using => :git, :tag => 'v3.1.6'

  depends_on "ruby"

  def install
    ENV["GEM_HOME"] = libexec
    system "gem", "build", "jekyll.gemspec"
    system "gem", "install", "jekyll-3.1.6.gem"
    bin.install "bin/jekyll"
    bin.env_script_all_files(libexec/"bin", :GEM_HOME => ENV["GEM_HOME"])
  end

  test do
    system "#{bin}/jekyll help"
  end
end
