#!/usr/bin/env ruby
require_relative '../lib/ident'
require 'slop'
def print(string)
  puts string.to_s unless @json
end

def print_debug(string)
  puts "[D] #{string}" if @debug && !@json
end

def main
  begin
    ###
    ### Parse options
    ###
    opts = Slop.parse do |o|
      # url input
      o.string '-u', '--uri', 'a uri to check (supported portocols: ' +
                              '(dns, elasticsearch, ftp, http, https, imap, mongodb, mysql, pop3, redis, smb, smtp, snmp, telnet, amqp, upnp) ' +
                              'ex: http://intrigue.io'
      o.string '-f', '--file', 'a file of urls, one per line'

      # export
      # o.bool '--csv', 'export to csv'
      o.bool '-j', '--json', 'export to json'

      # behavior
      o.string '-i', '--include', 'include checks from this directory (can be used multiple times)'
      o.integer '-t', '--threads', 'number of threads to use when checking a file (default: 3)'
      o.bool '-v', '--vulnerabilities', 'query intrigue.io api for top vulnerabilities'
      o.bool '-c', '--content', 'show content checks'
      o.bool '-b', '--only-check-base-url', 'only base url '
      o.bool '-d', '--debug', 'enable debug mode'
      o.bool '-l', '--list', 'list all checks'

      o.bool '-n', '--noisy', 'checks all known paths for fingerprints.'

      o.string '-w', '--checks-with-tag', 'filters by tags. ex -w "saas,iot" (combine with -n to check all known paths)'

      o.on '-h', '--help' do
        print o
        exit
      end

      o.on '--version', 'print the version' do
        print Ident::VERSION
        exit
      end
    end
  rescue Slop::MissingArgument => e
    print "Error! #{e}"
    return
  end

  # convert to a hash
  opts = opts.to_hash

  opts[:checks_with_tag] = opts[:checks_with_tag].to_s.split(',')

  # set json as a variable
  @json = opts[:json] if opts[:json]

  # set noisy as a variable
  @noisy = opts[:noisy] if opts[:noisy]

  # set debug as a variable
  @debug = opts[:debug] if opts[:debug]

  ###
  ## include external checks
  ###
  if opts[:include]
    # follow directory structure from ident
    checks = Dir.glob("#{opts[:include]}/checks/*.rb")
    checks += Dir.glob("#{opts[:include]}/checks/*/*.rb")
    checks += Dir.glob("#{opts[:include]}/checks/*/*/*.rb")
    print_debug "Requiring #{checks.count} files from include path: #{opts[:include]}"
    checks.each do |p|
      require p
    end
  end

  if opts[:list]
    print 'Fingerprint, Version Detection, Hide By Default, Issues, Vulnerability Inference, Tags'
    ident = Intrigue::Ident::Ident.new
    ident.list_checks.sort_by { |c| (c[:type]).to_s }.each do |c|
      next unless c[:type] == 'fingerprint'

      out = ''
      out << "#{c[:name]} #{c[:vendor]} #{c[:product]} #{c[:version]}".gsub(',', '') + ', '
      out << "#{!c[:dynamic_version].nil?}, "
      out << "#{c[:hide]}, "
      out << "#{(c[:issues].join(' | ') if c[:issues]) || c[:issue]}, "
      out << "#{c[:inference]}, "
      # out << "#{c[:paths].join(" | ") if c[:paths]}, "
      out << (c[:tags].join(' | ') if c[:tags]).to_s
      print out
    end
    return # so we don't hit the next gate
  end

  unless opts[:uri] || opts[:file] || opts[:list]
    print 'Error! At least one of --list, --file or --uri must be specified'
    return
  end

  ## handle url input
  if opts[:uri]
    print_debug "Checking URL: #{opts[:uri]}"
    check_single_uri(opts)
  end

  ## handle file input
  if opts[:file]
    print_debug "Checking File: #{opts[:file]}"
    check_uris_from_file(opts)
  end
end

def check_uris_from_file(opts)
  filepath = opts[:file]

  # push all urls into a queue
  work_q = Queue.new
  output_q = Queue.new

  print_debug "Parsing file #{filepath}"

  if filepath == "-"
    $stdin.each_line { |line| work_q << line.chomp }
  else
    File.open(filepath, 'r').each_line { |line| work_q << line.chomp }
  end

  # create a new ident obj
  ident_obj = Intrigue::Ident::Ident.new

  num_threads = opts[:threads] || 3
  workers = (0...num_threads).map do
    Thread.new do
      begin
        while (x = work_q.pop(true))
          thread_name = "thread-#{rand(9_999_999)}"
          print_debug "#{thread_name} checking: #{x}"

          # check_result = generate_http_requests_and_check(x, opts)
          check_result = ident_obj.fingerprint_uri(x)

          out = {}
          out['url'] = check_result['url']

          # get the fingerprint component, uniq it
          if check_result['fingerprint']
            out['fingerprint'] = []
            check_result['fingerprint'].each do |y|
              # Make sure not to include dupes, unless we're debugging
              next if out['fingerprint'].include?(y)

              out['fingerprint'] << y
            end
          end

          # get all the content check values as hash entries
          if check_result['content']
            out['content'] = {}
            check_result['content'].each do |y|
              out['content'][(y['name']).to_s] = y['result']
            end
          end

          out['responses'] = []
          if check_result['responses']
            out['responses'] = check_result['responses']
          end

          print_debug "#{thread_name} #{x} gave result: #{out}"

          output_q << check_result
        end
      rescue StandardError => e
        print_debug "Caught Exception! #{e}"
      rescue ThreadError => e
        print_debug "Caught Exception! #{e}"
      end
    end
  end; 'ok' # workers
  workers.map(&:join); 'ok'

  puts JSON.dump(Array.new(output_q.size) { output_q.pop })
end

def check_single_uri(opts)
  print_debug "Options: #{opts}"
  query_vulns = opts[:vulnerabilities] || false

  uri = opts[:uri]

  # parse the uri and fingerprint it through the main interface
  check_result = Intrigue::Ident::Ident.new.fingerprint_uri(uri, opts)

  if @debug && check_result['initial_checks'] && check_result['followon_checks']
    unless check_result['initial_checks'].empty?
      print_debug "Ran #{check_result['initial_checks'].first['count']} initial checks against base URL"
    end

    unless check_result['followon_checks'].empty?
      print_debug 'Also checked the following urls due to initial fingerprint:'
      check_result['followon_checks'].each { |x| print_debug " - #{x['url']}\n" }
    end

  end

  unless check_result
    print_debug 'Internal Error! Unable to get matches!'
    exit(-1)
  end

  if check_result['fingerprint'] && !@json
    print 'Fingerprint: '
    uniq_matches = []
    check_result['fingerprint'].each do |x|
      # Print it out
      print " - #{x['vendor']} #{x['product']} #{x['version']} #{x['update']} - #{x['description']} (CPE: #{x['cpe']}) (Tags: #{x['tags']}) (Hide: #{x['hide']}) (Issues: #{x['issues']}) (Tasks: #{x['tasks']})"

      # VULN QUERY PER FP
      next unless query_vulns # only proceed withthis section if we have vuln querying enabled
      vulns = Intrigue::Vulndb::Client.query(ENV['INTRIGUEIO_KEY'], x['cpe']) || []
      vulns.sort_by { |x| x['cvss_v3_score'] || x['cvss_v2_score'] || 1 }.reverse.first(5).each do |v|
        print "   - Vuln: #{v['cve']} (CVSS: #{v['cvss_v3_score'] || v['cvss_v2_score']}) https://nvd.nist.gov/vuln/detail/#{v['cve']}"
      end

    end
  elsif !@json
    print 'No fingerprint-able technologies discovered!'
  end

  if opts[:content] && (check_result['content'])
    print 'Content Checks:'
    check_result['content'].each do |x|
      print " - #{x['name']}: #{x['result']}"
    end
  end

  if @json
    # Not print, since that's blocked on @json
    puts JSON.pretty_generate(check_result)
  end

end

main
