# encoding: utf-8
# generate mhtml file 
# == uri target uri
# return mhtml file
#mhtml = MHT::MhtmlGenerator.generate("https://rubygems.org/")
#open("output.mht", "w+"){|f| f.write mhtml }
module MHT
require 'rubygems'
require 'nokogiri'
require 'open-uri'
require 'digest/md5'
require 'stringio'
require 'base64'
require 'thread'

# generate mhtml file 
# == uri target uri
# return mhtml file
#mhtml = MHT::MhtmlGenerator.generate("https://rubygems.org/")
#open("output.mht", "w+"){|f| f.write mhtml }
class MhtmlGenerator
  attr_accessor :conf
  def MhtmlGenerator.generate(uri)
    generateror = MhtmlGenerator.new
    return generateror.convert(uri)
  end
  def initialize
    @contents = {}
    @src = StringIO.new
    @boundary = "mimepart_#{Digest::MD5.hexdigest(Time.now.to_s)}"
    @threads  = []
    @queue    = Queue.new
    @conf     = { :base64_except=>["html"]}
  end
  def convert(filename_or_uri)
      f = open(filename_or_uri)
      html = f.read
      @parser = Nokogiri::HTML html
      @src.puts "Subject: " + @parser.search("title").text()
      @src.puts "Content-Type: multipart/related; boundary=#{@boundary}"
      @src.puts "Content-Location: #{filename_or_uri}"
      @src.puts "Date: #{Time.now.to_s}"
      @src.puts "MIME-Version: 1.0"
      @src.puts ""
      @src.puts "mime mhtml content"
      @src.puts ""
      #imgs
      @parser.search('img').each{|i| 
          uri = i.attr('src');
          uri = URI::join( filename_or_uri, uri).to_s
          uid = Digest::MD5.hexdigest(uri)
          @contents[uid] = uri
          i.set_attribute('src',"cid:#{uid}")
        }
      #styles
      @parser.search('link[rel=stylesheet]').each{|i|
          uri = i.attr('href');
          uri = URI::join( filename_or_uri, uri).to_s
          uid = Digest::MD5.hexdigest(uri)
          @contents[uid] = uri
          i.set_attribute('href',"cid:#{uid}")
        }
      #scripts
      @parser.search('script').map{ |i|
          next unless i.attr('src');
          uri = i.attr('src');
          uri = URI::join( filename_or_uri, uri).to_s
          uid = Digest::MD5.hexdigest(uri)
          @contents[uid] = uri
          i.set_attribute('src',"cid:#{uid}")
      }
      @src.puts "--#{@boundary}"
      @src.puts "Content-Disposition: inline; filename=default.htm"
      @src.puts "Content-Type: #{f.meta['content-type']}"
      @src.puts "Content-Id: #{Digest::MD5.hexdigest(filename_or_uri)}"
      @src.puts "Content-Location: #{filename_or_uri}"
      @src.puts "Content-Transfer-Encoding: 8bit" if @conf[:base64_except].find("html")
      @src.puts "Content-Transfer-Encoding: Base64" unless @conf[:base64_except].find("html")
      @src.puts ""
      #@src.puts html
      @src.puts "#{html}"                      if @conf[:base64_except].find("html")
      #@src.puts "#{Base64.encode64(html)}" unless @conf[:base64_except].find("html")
      @src.puts ""
      self.attach_contents
      @src.puts "--#{@boundary}--"
      @src.rewind
      return @src.read
  end
  def start_download_thread(num=5)
    num.times{
      t = Thread.start{
        while(@queue.empty? == false)
          k = @queue.pop
          v = @contents[k]
          next if v.class == Hash
          f = open(v)
          meta = f.meta
          @contents[k] = { :body=>f.read, :uri=> v, :content_type=> f.meta["content-type"] }
        end
      }
      @threads.push t
    }
    return @threads
  end
  def download_finished?
    @contents.find{|k,v| v.class != Hash } == nil
  end
  def attach_contents
    #prepeare_queue
    @contents.each{|k,v| @queue.push k}
    #start download threads
    self.start_download_thread
    # wait until download finished.
    @threads.each{|t|t.join}
    @contents.each{|k,v|self.add_html_content(k)}
  end
  def add_html_content(cid)
    filename = File.basename(URI(@contents[cid][:uri]).path)
    @src.puts "--#{@boundary}"
    @src.puts "Content-Disposition: inline; filename=" + filename 
    @src.puts "Content-Type: #{@contents[cid][:content_type]}"
    @src.puts "Content-Location: #{@contents[cid][:uri]}"
    @src.puts "Content-Transfer-Encoding: Base64"
    @src.puts "Content-Id: #{cid}"
    @src.puts ""
    @src.puts "#{Base64.encode64(@contents[cid][:body])}"
    @src.puts ""
     return
  end
end

end
