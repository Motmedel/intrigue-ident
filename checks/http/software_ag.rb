module Intrigue
  module Ident
  module Check
  class SoftwareAg < Intrigue::Ident::Check::Base
  
    def generate_checks(url)
      [
        {
          :type => "fingerprint",
          :category => "application",
          :tags => ["COTS"],
          :vendor => "Software AG",
          :product => "webMethods Nirvana Messaging",
          :references => ["http://www.universalmessaging.org/"],
          :match_details => "server header",
          :version => nil,
          :match_type => :content_headers,
          :match_content =>  /server: my-Channels/i,
          :paths => ["#{url}"],
          :inference => false
        },
        {
          :type => "fingerprint",
          :category => "application",
          :tags => ["COTS"],
          :vendor => "Software AG",
          :product => "webMethods Nirvana Messaging",
          :references => ["http://www.universalmessaging.org/"],
          :match_details => "documentation index version",
          :version => nil,
          :match_type => :content_body,
          :match_content =>  /<h1>Nirvana [\d\.]+ Documentation Index/i,
          :dynamic_version => lambda{|x| _first_body_capture(x,/<h1>Nirvana ([\d\.]+) Documentation Index/i)},
          :paths => ["#{url}"],
          :inference => false
        }
      ]
    end


    
  
  end
  end
  end
  end
  