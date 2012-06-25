require 'helper'

class TestWebPageArchiver < Test::Unit::TestCase
  def test_generate_remote
    mhtml = WebPageArchiver::MhtmlGenerator.generate("http://murb.github.com/web-page-archiver/static/")
    assert(mhtml.match('touXAzfbxedaI8CBEZgixpEx0oFD'))
    assert(mhtml.match(/Content-Disposition: inline; filename=test.js\nContent-Type: application\/(.*)javascript\nContent-Location: (.*)test.js\nContent-Transfer-Encoding: Base64\nContent-Id: (.*)\n\nZnVuY3Rpb24gdGVzdCgpIHsKCWFsZXJ0KCd0ZXN0Jyk7Cn0=/))
  end
  
  def test_generate_local
    mhtml = WebPageArchiver::MhtmlGenerator.generate("fixtures/index.html")
    assert(mhtml.match('touXAzfbxedaI8CBEZgixpEx0oFD'))
    assert(mhtml.match(/Content-Disposition: inline; filename=test.js\nContent-Type: application\/(.*)javascript\nContent-Location: (.*)test.js\nContent-Transfer-Encoding: Base64\nContent-Id: (.*)\n\nZnVuY3Rpb24gdGVzdCgpIHsKCWFsZXJ0KCd0ZXN0Jyk7Cn0=/))
  end
  
  
end
