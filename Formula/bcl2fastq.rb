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

  def install
    ohai "Your files, sir:", Dir["*"]
  end

  test do

  end
end
