# encoding: utf-8

module WebPageArchiver

  require 'nokogiri'
  require 'open-uri'
  require 'digest/md5'
  require 'stringio'
  require 'base64'
  require 'thread'
  require 'mime/types'

  # Generic methods
  # To reuse in both the MhtmlGenerator as the InlineHtmlGenerator
  module GeneratorHelpers
    def initialize
      @contents = {}
      @src = StringIO.new
      @boundary = "mimepart_#{Digest::MD5.hexdigest(Time.now.to_s)}"
      @threads  = []
      @queue    = Queue.new
      @conf     = { :base64_except=>["html"] }
    end

    # Creates a absolute URI-string for referenced resources in base file name
    #
    # @param [String, URI] base_filename_or_uri from where the resource is linked
    # @param [String] path of the resource (relative or absolute) within the parent resource
    # @return [String] URI-string
    def join_uri(base_filename_or_uri, path)
      puts base_filename_or_uri
      stream = open(base_filename_or_uri)
      joined = ""
      if stream.is_a? File
        base_filename_or_uri = base_filename_or_uri.path if base_filename_or_uri.is_a? File

        windows_drive_matcher = /((.*):\/)/
        windows_drive_match_data = base_filename_or_uri.match windows_drive_matcher
        if windows_drive_match_data
          base_filename_or_uri = base_filename_or_uri.gsub(windows_drive_matcher,'WINDOWS.DRIVE/')
        end

        joined = URI::join("file://#{base_filename_or_uri}", path)
        joined = joined.to_s.gsub('file://','').gsub('file:','')

        if windows_drive_match_data
          joined = joined.gsub('WINDOWS.DRIVE/',windows_drive_match_data[1])
        end
      else
        joined = URI::join(base_filename_or_uri, path)
      end
      return joined.to_s
    end

    # Determines the conttent type of a file or download
    #
    # @param [File,URI] object to test
    # @return [String] mime-type / content type
    def content_type(object)
      if object.is_a? File
        return MIME::Types.type_for(object.path).first
      else
        return object.meta["content-type"]
      end
    end

    # Processes the download queue
    #
    # @param [Integer] num number of threads
    # @return [Array<Thread>] the ruby-threads opened
    def start_download_thread(num=5)
      num.times{
        t = Thread.start{
          while(@queue.empty? == false)
            k = @queue.pop
            next if @contents[k][:body] != nil
            v = @contents[k][:uri]
            f = open(v)
            @contents[k] = @contents[k].merge({ :body=>f.read, :uri=> v, :content_type=> content_type(f) })
          end
        }
        @threads.push t
      }
      return @threads
    end

    # Tests wether all the required content has been downloaded
    def download_finished?
      @contents.find{|k,v| v[:body] == nil } == nil
    end
  end

  # generates mht-files
  class MhtmlGenerator
    include GeneratorHelpers
    attr_accessor :conf

    # generate mhtml (mht) file without instantiating a MhtmlGenerator object
    #
    # mhtml = WebPageArchiver::MhtmlGenerator.generate("https://rubygems.org/")
    # open("output.mht", "w+"){|f| f.write mhtml }
    #
    # @param [String, URI] filename_or_uri to test for
    # @return [String] text blob containing the result
    def MhtmlGenerator.generate(filename_or_uri)
      generator = MhtmlGenerator.new
      return generator.convert(filename_or_uri)
    end

    # convert object at uri to self-contained text-file
    #
    # @param [String, URI] filename_or_uri to test for
    # @return [String] text blob containing the result
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
            uri = join_uri( filename_or_uri, uri).to_s
            uid = Digest::MD5.hexdigest(uri)
            @contents[uid] = {:uri=>uri}
            i.set_attribute('src',"cid:#{uid}")
          }
        #styles
        @parser.search('link[rel=stylesheet]').each{|i|
            uri = i.attr('href');
            uri = join_uri( filename_or_uri, uri)
            uid = Digest::MD5.hexdigest(uri)
            @contents[uid] = {:uri=>uri}
            i.set_attribute('href',"cid:#{uid}")
          }
        #scripts
        @parser.search('script').map{ |i|
            next unless i.attr('src');
            uri = i.attr('src');
            uri = join_uri( filename_or_uri, uri)
            uid = Digest::MD5.hexdigest(uri)
            @contents[uid] = {:uri=>uri}
            i.set_attribute('src',"cid:#{uid}")
        }
        @src.puts "--#{@boundary}"
        @src.puts "Content-Disposition: inline; filename=default.htm"
        @src.puts "Content-Type: #{content_type(f)}"
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

    # adds mime-parts
    def attach_contents
      #prepeare_queue
      @contents.each{|k,v| @queue.push k}
      #start download threads
      self.start_download_thread
      # wait until download finished.
      @threads.each{|t|t.join}
      @contents.each{|k,v|self.add_html_content(k)}
    end

    # helper method to generate proper mime part headers
    #
    # param [String] cid content ID
    # return [String] mime-part-text-blob
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

  # self-containing data-uri based html
  class DataUriHtmlGenerator
    include GeneratorHelpers

    attr_accessor :conf

    # generate self-containing data-uri based html file (html) file without instantiating a MhtmlGenerator object
    #
    # mhtml = WebPageArchiver::DataUriHtmlGenerator.generate("https://rubygems.org/")
    # open("output.html", "w+"){|f| f.write mhtml }
    #
    # @param [String, URI] filename_or_uri to test for
    # @return [String] text blob containing the result
    def DataUriHtmlGenerator.generate(filename_or_uri)
      generateror = DataUriHtmlGenerator.new
      return generateror.convert(filename_or_uri)
    end

    # convert object at uri to self-contained text-file
    #
    # @param [String, URI] filename_or_uri to test for
    # @return [String] text blob containing the result
    def convert(filename_or_uri)
        @parser = Nokogiri::HTML(open(filename_or_uri))
        @parser.search('img').each{|i|
            uri = i.attr('src');
            uri = join_uri( filename_or_uri, uri).to_s
            uid = Digest::MD5.hexdigest(uri)
            @contents[uid] = {:uri=>uri, :parser_ref=>i, :attribute_name=>'src'}
            i.set_attribute('src',"cid:#{uid}")
          }
        #styles
        @parser.search('link[rel=stylesheet]').each{|i|
            uri = i.attr('href');
            uri = join_uri( filename_or_uri, uri)
            uid = Digest::MD5.hexdigest(uri)
            @contents[uid] = {:uri=>uri, :parser_ref=>i, :attribute_name=>'href'}
            i.set_attribute('href',"cid:#{uid}")
          }
        #scripts
        @parser.search('script').map{ |i|
            next unless i.attr('src');
            uri = i.attr('src');
            uri = join_uri( filename_or_uri, uri)
            uid = Digest::MD5.hexdigest(uri)
            @contents[uid] = {:uri=>uri, :parser_ref=>i, :attribute_name=>'src'}
            i.set_attribute('src',"cid:#{uid}")
        }
        self.set_contents
        return @parser.to_s
    end

    # replaces content-placeholders with actual content
    def set_contents
      #prepeare_queue
      @contents.each{|k,v| @queue.push k}
      #start download threads
      self.start_download_thread
      # wait until download finished.
      @threads.each{|t|t.join}
      @contents.each do |k,v|
        content_benc=Base64.encode64(v[:body]).gsub(/\n/,'')
        tag=v[:parser_ref]
        attribute=v[:attribute_name]
        content_type=v[:content_type]
        tag.set_attribute(attribute,"data:#{content_type};base64,#{content_benc}")
      end
    end
  end

  # self-containing all-inline based html
  class InlineHtmlGenerator
    include GeneratorHelpers

    attr_accessor :conf

    # generate self-containing all-inline based html file (html) file without instantiating a MhtmlGenerator object
    #
    # mhtml = WebPageArchiver::InlineHtmlGenerator.generate("https://rubygems.org/")
    # open("output.html", "w+"){|f| f.write mhtml }
    #
    # @param [String, URI] filename_or_uri to test for
    # @return [String] text blob containing the result
    def InlineHtmlGenerator.generate(filename_or_uri)
      generator = InlineHtmlGenerator.new
      return generator.convert(filename_or_uri)
    end

    # convert object at uri to self-contained text-file
    #
    # @param [String, URI] filename_or_uri to test for
    # @return [String] text blob containing the result
    def convert(filename_or_uri)
        @parser = Nokogiri::HTML(open(filename_or_uri))
        @parser.search('img').each{|i|
            uri = i.attr('src');
            uri = join_uri( filename_or_uri, uri).to_s
            uid = Digest::MD5.hexdigest(uri)
            @contents[uid] = {:uri=>uri, :parser_ref=>i, :attribute_name=>'src'}
            i.set_attribute('src',"cid:#{uid}")
          }
        #styles
        @parser.search('link[rel=stylesheet]').each{|i|
            uri = i.attr('href');
            uri = join_uri( filename_or_uri, uri)
            uid = Digest::MD5.hexdigest(uri)
            @contents[uid] = {:uri=>uri, :parser_ref=>i, :attribute_name=>'href'}
            i.set_attribute('href',"cid:#{uid}")
          }
        #scripts
        @parser.search('script').map{ |i|
            next unless i.attr('src');
            uri = i.attr('src');
            uri = join_uri( filename_or_uri, uri)
            uid = Digest::MD5.hexdigest(uri)
            @contents[uid] = {:uri=>uri, :parser_ref=>i, :attribute_name=>'src'}
            i.set_attribute('src',"cid:#{uid}")
        }
        self.set_contents
        return @parser.to_s
    end

    def set_contents
      #prepeare_queue
      @contents.each{|k,v| @queue.push k}
      #start download threads
      self.start_download_thread
      # wait until download finished.
      @threads.each{|t|t.join}
      @contents.each do |k,v|
        tag=v[:parser_ref]
        if tag.name == "script"
          content_benc=Base64.encode64(v[:body]).gsub(/\n/,'')
          attribute=v[:attribute_name]
          content_type=v[:content_type]
          tag.content=v[:body]
          tag.remove_attribute(v[:attribute_name])
        elsif tag.name == "link" and v[:content_type]="text/css"
          tag.after("<style type=\"text/css\">#{v[:body]}</style>")
          tag.remove()
        else
          # back to inline for non-script and style files...
          content_benc=Base64.encode64(v[:body]).gsub(/\n/,'')
          attribute=v[:attribute_name]
          content_type=v[:content_type]
          tag.set_attribute(attribute,"data:#{content_type};base64,#{content_benc}")
        end
      end
    end
  end
end
