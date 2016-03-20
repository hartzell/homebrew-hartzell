# Illumina has their tar.gz file inside a zip file.  Sigh...
# Extend the Curl.... to handle it.
class ZippedTGZStrategy < CurlDownloadStrategy
  def stage
    with_system_path { quiet_safe_system "unzip", { :quiet_flag => "-qq" }, cached_location }
    chdir
    tar_flags = (ARGV.verbose? && ENV["TRAVIS"].nil?) ? "xvf" : "xf"
    with_system_path { safe_system "tar", tar_flags, "bcl2fastq2-v2.17.1.14.tar.gz" }
    Dir.chdir( "bcl2fastq")
  end
end

# Class name needs to be leading cap.
class Bcl2fastq < Formula
  desc "Convert BCL files to fastq"
  homepage "http://support.illumina.com/downloads/bcl2fastq-conversion-software-v217.html"
  url "ftp://webdata2:webdata2@ussd-ftp.illumina.com/downloads/software/bcl2fastq/bcl2fastq2-v2.17.1.14.tar.zip",
      :using => ZippedTGZStrategy
  sha256 "3cf566f8bf02629e4367015511802680dc5481d44ff79559b186705f68f80c27"

  depends_on "boost" => :build
  depends_on "cmake" => :build

  resource "zlib" do
    url "http://zlib.net/zlib-1.2.8.tar.gz"
    sha256 "36658cb768a54c1d4dec43c3116c27ed893e88b02ecfcb44f2166f9c0b7f2a0d"
  end

  def install
    ohai "Your files, sir:", Dir["*"]
  end

  test do

  end
end
