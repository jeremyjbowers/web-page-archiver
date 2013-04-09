require 'helper'

class TestWebPageArchiver < Test::Unit::TestCase
  def test_generate_mht_remote
    mhtml = WebPageArchiver::MhtmlGenerator.generate("http://murb.github.com/web-page-archiver/static/")
    assert(mhtml.match('touXAzfbxedaI8CBEZgixpEx0oFD'))
    assert(mhtml.match(/Content-Disposition: inline; filename=test.js\nContent-Type: application\/(.*)javascript\nContent-Location: (.*)test.js\nContent-Transfer-Encoding: Base64\nContent-Id: (.*)\n\nZnVuY3Rpb24gdGVzdCgpIHsKCWFsZXJ0KCd0ZXN0Jyk7Cn0=/))
  end
  
  def test_generate_mht_local
    mhtml = WebPageArchiver::MhtmlGenerator.generate("fixtures/index.html")
    assert(mhtml.match('touXAzfbxedaI8CBEZgixpEx0oFD'))
    assert(mhtml.match(/Content-Disposition: inline; filename=test.js\nContent-Type: application\/(.*)javascript\nContent-Location: (.*)test.js\nContent-Transfer-Encoding: Base64\nContent-Id: (.*)\n\nZnVuY3Rpb24gdGVzdCgpIHsKCWFsZXJ0KCd0ZXN0Jyk7Cn0=/))
  end
  
  def test_generate_html_local
    mhtml = WebPageArchiver::DataUriHtmlGenerator.generate("fixtures/index.html")
    assert(mhtml.match('touXAzfbxedaI8CBEZgixpEx0oFD'))
    assert(mhtml.match('<img src="data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAIAAAACACAYAAADDPmHLAAAACXBIWXMAABYlAAAWJQFJUiTwAAAAGXRFWHRTb2Z0d2'))
    assert(mhtml.match('<script type="text/javascript" src="data:application/javascript;base64,ZnVuY3Rpb24gdGVzdCgpIHsKCWFsZXJ0KCd0ZXN0Jyk7Cn0="></script><link rel="stylesheet" href="data:text/css;base64,aDEgewoJY29sb3I6IGdyZWVuOwp9" type="text/css" charset="utf-8">'))
  end
  
  def test_generate_inline_html_local
    mhtml = WebPageArchiver::InlineHtmlGenerator.generate("fixtures/index.html")
    assert(mhtml.match("alert"))
    assert(mhtml.match('color: green;'))
    assert(mhtml.match('<img src="data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAIAAAACACAYAAADDPmHLAAAACXBIWXMAABYlAAAWJQFJUiTwAAAAGXRFWHRTb2Z0d2'))
  end


  class JoinUriTestClass
    include WebPageArchiver::GeneratorHelpers
  end
  
  def test_join_uri
    a = JoinUriTestClass.new
    assert_equal("http://murb.github.com/web-page-archiver/static/asdf", a.join_uri("http://murb.github.com/web-page-archiver/static/","asdf"))
    assert_equal("http://murb.github.com/web-page-archiver/asdf", a.join_uri("http://murb.github.com/web-page-archiver/static","asdf"))
    assert_equal("http://google.com", a.join_uri("http://murb.github.com/web-page-archiver/static","http://google.com"))
    
    # this test will fail on Windows ...
    Dir.mkdir 'C:' unless File.exists?('C:')
    Dir.mkdir 'C:/testingdir/' unless File.exists?('C:/testingdir')
    assert_equal("C:/test", a.join_uri(File.open("C:/testing", 'w+'),"test"))
    assert_equal("C:/testingdir/test", a.join_uri(File.open("C:/testingdir/a", 'w+'),"test"))
    File.delete 'C:/testingdir/a'
    Dir.rmdir 'C:/testingdir/' 
    File.delete 'C:/testing'
    Dir.rmdir 'C:'
    
  end
end
