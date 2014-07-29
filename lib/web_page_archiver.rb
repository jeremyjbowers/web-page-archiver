# encoding: utf-8

module WebPageArchiver

  require 'nokogiri'
  require 'open-uri'
  require 'digest/md5'
  require 'stringio'
  require 'base64'
  require 'thread'
  require 'mime/types'
  require 'typhoeus'
  require 'colorize'

  module GeneratorHelpers
    def initialize
      @contents = {}
      @src = StringIO.new
      @boundary = "mimepart_#{Digest::MD5.hexdigest(Time.now.to_s)}"
      @threads = []
      @queue = Queue.new
      @conf = { :base64_except=>["html"] }
    end

    # Creates a absolute URI-string for referenced resources in base file name
    #
    # @param [String, URI] base_filename_or_uri from where the resource is linked
    # @param [String] path of the resource (relative or absolute) within the parent resource
    # @return [String] URI-string
    #
    def join_uri(base_filename_or_uri, path)
      stream = ""
      begin
        stream = open(base_filename_or_uri)
      rescue => ex
        print "!R".colorize(:red)
        print " \"#{ex}\" ".gsub("\n", " ").gsub("\r", " ").colorize(:yellow)
        sleep(3.seconds)
        stream = open(base_filename_or_uri)
      end

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

    # Determines the contenttype of a file or download
    #
    # @param [File,URI] object to test
    # @return [String] mime-type / content type
    #
    def content_type(obj)
      if obj.is_a? File
        return MIME::Types.type_for(obj.path).first
      else
        return obj.headers_hash["content-type"]
      end
    end

    # Processes the download queue
    #
    # @param [Integer] num number of threads
    # @return [Array<Thread>] the ruby-threads opened
    #
    def start_download_thread
      2.times{
        t = Thread.start{
          while(@queue.empty? == false)
            retry_counter = 0
            k = @queue.pop
            next if @contents[k][:body] != nil

            v = @contents[k][:uri]
            print "+".colorize(:green)

            f = ""

            begin
              f = Typhoeus.get(v)
            rescue => ex
              print "R!".colorize(:red)
              print " \"#{ex}\" ".gsub("\n", " ").gsub("\r", " ").colorize(:yellow)
              sleep(3.seconds)
              f = Typhoeus.get(v)
            end
            @contents[k] = @contents[k].merge({ :body=>f.body.to_s, :uri=> v, :content_type=> content_type(f) })
          end
        }
        @threads.push t
      }
      return @threads
    end

    def download_finished?
      @contents.find{|k,v| v[:body] == nil } == nil
    end
  end

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
    #
    def DataUriHtmlGenerator.generate(filename_or_uri)
      g = DataUriHtmlGenerator.new
      return g.convert(filename_or_uri)
    end

    # convert object at uri to self-contained text-file
    #
    # @param [String, URI] filename_or_uri to test for
    # @return [String] text blob containing the result
    #
    def convert(filename_or_uri)
      base_file = ""
      begin
        base_file = Typhoeus.get(filename_or_uri)
      rescue => ex
        print "!H".colorize(:red)
        print " \"#{ex}\" ".gsub("\n", " ").gsub("\r", " ").colorize(:yellow)
        sleep(3.seconds)
        base_file = Typhoeus.get(filename_or_uri)
      end

      @parser = Nokogiri::HTML(base_file.body.to_s)

      @parser.search('img').each { |i|
        uri = i.attr('src')
        uri = URI.encode(uri)
        uri = join_uri( filename_or_uri, uri).to_s
        uid = Digest::MD5.hexdigest(uri)
        @contents[uid] = {:uri=>uri, :parser_ref=>i, :attribute_name=>'src'}
        i.set_attribute('src',"cid:#{uid}")
      }

      @parser.search('link[rel=stylesheet]').each { |i|
        uri = i.attr('href')
        uri = URI.encode(uri)
        uri = join_uri( filename_or_uri, uri)
        uid = Digest::MD5.hexdigest(uri)
        @contents[uid] = {:uri=>uri, :parser_ref=>i, :attribute_name=>'href'}
        i.set_attribute('href',"cid:#{uid}")
      }

      @parser.search('script').each { |i|
        next unless i.attr('src')
        uri = i.attr('src')
        uri = URI.encode(uri)
        uri = join_uri( filename_or_uri, uri)
        uid = Digest::MD5.hexdigest(uri)
        @contents[uid] = {:uri=>uri, :parser_ref=>i, :attribute_name=>'src'}
        i.set_attribute('src',"cid:#{uid}")
      }

      self.set_contents
      return @parser.to_s
    end

    def set_contents
      @contents.each{ |k,v| @queue.push k }
      self.start_download_thread
      @threads.each{ |t| t.join }
      @contents.each { |k,v|
        content_benc = Base64.encode64(v[:body]).gsub(/\n/,'')
        tag = v[:parser_ref]
        attribute = v[:attribute_name]
        content_type = v[:content_type]
        tag.set_attribute(attribute,"data:#{content_type};base64,#{content_benc}")
      }
    end

  end
end
