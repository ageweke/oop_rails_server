require 'fileutils'
require 'find'
require 'net/http'
require 'uri'
require 'file/tail'
require 'oop_rails_server/gemfile'

module OopRailsServer
  class RailsServer
    attr_reader :rails_root, :rails_version, :name, :actual_rails_version, :actual_ruby_version, :actual_ruby_engine

    def initialize(options)
      options.assert_valid_keys(
        :name, :template_paths, :runtime_base_directory,
        :rails_version, :rails_env, :gemfile_modifier,
        :log, :verbose
      )

      @name = options[:name] || raise(ArgumentError, "You must specify a name for the Rails server")

      @template_paths = options[:template_paths] || raise(ArgumentError, "You must specify one or more template paths")
      @template_paths = Array(@template_paths).map { |t| File.expand_path(t) }
      @template_paths = base_template_directories + @template_paths

      @runtime_base_directory = options[:runtime_base_directory] || raise(ArgumentError, "You must specify a runtime_base_directory")
      @runtime_base_directory = File.expand_path(@runtime_base_directory)

      @rails_version = options[:rails_version] || :default
      @rails_env = (options[:rails_env] || 'production').to_s

      @log = options[:log] || $stderr
      @verbose = options.fetch(:verbose, true)

      @gemfile_modifier = options[:gemfile_modifier] || (Proc.new { |gemfile| })


      @rails_root = File.expand_path(File.join(@runtime_base_directory, rails_version.to_s, name.to_s))
      @port = 20_000 + rand(10_000)
      @server_pid = nil
    end

    def start!
      do_start! unless server_pid
    end

    def setup!
      @set_up ||= begin
        Bundler.with_clean_env do
          with_rails_env do
            setup_directories!

            in_rails_root_parent do
              splat_bootstrap_gemfile!
              rails_new!
              update_gemfile!
            end

            in_rails_root do
              run_bundle_install!(:primary)
              splat_template_files!
            end
          end
        end

        true
      end
    end

    def stop!
      stop_server! if server_pid
    end

    def post(path_or_uri, options = { })
      send_http_request(path_or_uri, options.merge(:http_method => :post))
    end

    def get(path_or_uri, options = { })
      out = get_response(path_or_uri, options)
      out.body.strip if out
    end

    def uri_for(path_or_uri, query_values = nil)
      query_values ||= { }

      if path_or_uri.kind_of?(::URI)
        path_or_uri
      else
        uri_string = "http://#{localhost_name}:#{@port}/#{path_or_uri}"
        if query_values.length > 0
          uri_string += ("?" + query_values.map { |k,v| "#{CGI.escape(k.to_s)}=#{CGI.escape(v.to_s)}" }.join("&"))
        end
        URI.parse(uri_string)
      end
    end

    def localhost_name
      "127.0.0.1"
    end

    def send_http_request(path_or_uri, options = { })
      options.assert_valid_keys(:ignore_status_code, :nil_on_not_found, :query, :no_layout, :accept_header, :http_method, :post_variables)

      uri = uri_for(path_or_uri, options[:query])
      data = nil
      accept_header = options.fetch(:accept_header, 'text/html')

      http_method = options[:http_method] || :get

      Net::HTTP.start(uri.host, uri.port) do |http|
        klass = Net::HTTP.const_get(http_method.to_s.strip.camelize)
        request = klass.new(uri.to_s)

        if options[:post_variables]
          request.set_form_data(options[:post_variables])
        end

        request['Accept'] = accept_header if accept_header
        data = http.request(request)
      end

      if (data.code.to_s != '200')
        if options[:ignore_status_code]
          # ok, nothing
        elsif options[:nil_on_not_found]
          data = nil
        else
          raise "'#{uri}' returned #{data.code.inspect}, not 200; body was: #{data.body.inspect}"
        end
      end
      data
    end

    def get_response(path_or_uri, options = { })
      send_http_request(path_or_uri, options.merge(:http_method => :get))
    end

    def run_command_in_rails_root!(command)
      Bundler.with_clean_env do
        with_rails_env do
          in_rails_root do
            safe_system("bundle exec #{command}")
          end
        end
      end
    end

    private
    attr_reader :template_paths, :runtime_base_directory, :rails_env, :gemfile_modifier, :port, :server_pid

    def base_template_directories
      [
        File.expand_path(File.join(File.dirname(__FILE__), '../../templates/oop_rails_server_base'))
      ]
    end

    def do_start!
      setup!

      Bundler.with_clean_env do
        with_rails_env do
          in_rails_root do
            start_server!
            verify_server_and_shut_down_if_fails!
          end
        end
      end
    end

    def with_rails_env
      old_rails_env = ENV['RAILS_ENV']
      begin
        ENV['RAILS_ENV'] = rails_env
        yield
      ensure
        ENV['RAILS_ENV'] = old_rails_env
      end
    end

    def raise_startup_failed_error!(elapsed_time, exception)
      last_lines = server_logfile = nil
      if File.exist?(server_output_file) && File.readable?(server_output_file)
        server_logfile = server_output_file
        File::Tail::Logfile.open(server_output_file, :break_if_eof => true) do |f|
          f.extend(File::Tail)
          last_lines ||= [ ]
          begin
            f.tail(100) { |l| last_lines << l }
          rescue File::Tail::BreakException
            # ok
          end
        end
      end

      raise FailedStartupError.new(elapsed_time, exception, server_logfile, last_lines)
    end

    def setup_directories!
      return if @directories_setup

      template_paths.each do |template_path|
        raise Errno::ENOENT, "You must specify template paths that exist; this doesn't: '#{template_path}'" unless File.directory?(template_path)
      end
      FileUtils.rm_rf(rails_root) if File.exist?(rails_root)
      FileUtils.mkdir_p(rails_root)

      @directories_setup = true
    end

    def in_rails_root(&block)
      Dir.chdir(rails_root, &block)
    end

    def in_rails_root_parent(&block)
      Dir.chdir(File.dirname(rails_root), &block)
    end

    def splat_bootstrap_gemfile!
      rails_version_specs = if rails_version == :default then [ ] else [ "= #{rails_version}" ] end

      gemfile = ::OopRailsServer::Gemfile.new("Gemfile")
      gemfile.add_version_constraints!("rails", *rails_version_specs)

      backcompat_bootstrap_gems!(gemfile)

      gemfile.write!
      run_bundle_install!(:bootstrap)
    end

    def rails_new!
      # This is a little trick to specify the exact version of Rails you want to create it with...
      # http://stackoverflow.com/questions/379141/specifying-rails-version-to-use-when-creating-a-new-application
      rails_version_spec = rails_version == :default ? "" : "_#{rails_version}_"
      cmd = "bundle exec rails #{rails_version_spec} new #{File.basename(rails_root)} -d sqlite3 -f -B"
      safe_system(cmd, "creating a new Rails installation for '#{name}'")
    end

    def update_gemfile!
      gemfile = ::OopRailsServer::Gemfile.new(File.join(rails_root, 'Gemfile'))

      backcompat_bootstrap_gems!(gemfile)

      backcompat_execjs!(gemfile)
      backcompat_uglifier!(gemfile)

      gemfile_modifier.call(gemfile)

      gemfile.write!
    end

    def with_env(new_env)
      old_env = { }
      new_env.keys.each { |k| old_env[k] = ENV[k] }

      begin
        set_env(new_env)
        yield
      ensure
        set_env(old_env)
      end
    end

    def set_env(new_env)
      new_env.each do |k,v|
        if v
          ENV[k] = v
        else
          ENV.delete(k)
        end
      end
    end

    def splat_template_files!
      @template_paths.each do |template_path|
        Find.find(template_path) do |file|
          next unless File.file?(file)

          if file[0..(template_path.length)] == "#{template_path}/"
            subpath = file[(template_path.length + 1)..-1]
          else
            raise "#{file} isn't under #{template_path}?!?"
          end
          dest_file = File.join(rails_root, subpath)

          FileUtils.mkdir_p(File.dirname(dest_file))
          FileUtils.cp(file, dest_file)
        end
      end
    end

    def server_output_file
      @server_output_file ||= File.join(rails_root, 'log', 'rails-server.out')
    end

    START_SERVER_TIMEOUT = 30

    def start_server!
      output = server_output_file
      cmd = "bundle exec rails server -p #{port} > '#{output}' 2>&1"
      safe_system(cmd, "starting 'rails server' on port #{port}", :background => true)

      server_pid_file = File.join(rails_root, 'tmp', 'pids', 'server.pid')

      start_time = Time.now
      while Time.now < start_time + START_SERVER_TIMEOUT
        if File.exist?(server_pid_file)
          server_pid = File.read(server_pid_file).strip
          if server_pid =~ /^(\d{1,10})$/i
            @server_pid = Integer(server_pid)
            break
          end
        end

        sleep 0.1
      end

      unless server_pid
        raise "Unable to start the Rails server even after #{Time.now - start_time} seconds; there seems to be no file at '#{server_pid_file}', or no PID in that file if it does exist. Help!"
      end
    end

    def verify_server_and_shut_down_if_fails!
      begin
        verify_server!
      rescue Exception => e
        say "Verification of Rails server failed:\n  #{e.message} (#{e.class.name})\n    #{e.backtrace.join("\n    ")}"
        begin
          stop_server!
        rescue Exception => e
          say "WARNING: Verification of server failed, so we tried to stop it, but we couldn't do that. Proceeding, but you may have a Rails server left around anyway. The exception from trying to stop the server was:\n  #{e.message} (#{e.class.name})\n    #{e.backtrace.join("\n    ")}"
        end

        raise
      end
    end

    class FailedStartupError < StandardError
      attr_reader :timeout, :verify_exception_or_message, :server_logfile, :last_lines

      def initialize(timeout, verify_exception_or_message, server_logfile, last_lines)
        message = %{The out-of-process Rails server failed to start up properly and start responding to requests,
even after #{timeout.round} seconds. This typically means you've added code that prevents it from
even starting up -- most likely, a syntax error in a class or other error that stops it
dead in its tracks. (oop_rails_server starts up Rails servers in the production environment
by default, and, in production, Rails eagerly loads all classes at startup time.)}

        if server_logfile
          message << %{

Any errors will be located in the stdout/stderr of the Rails process, which is at:
  '#{server_logfile}'}
        end

        if last_lines
          message << %{

The last #{last_lines.length} lines of this log are:

#{last_lines.join("\n")}}
        end

        super(message)

        @timeout = timeout
        @verify_exception_or_message = verify_exception_or_message
        @server_logfile = server_logfile
        @last_lines = last_lines
      end
    end

    SERVER_VERIFY_TIMEOUT = 30

    def verify_server!
      server_verify_url = "http://#{localhost_name}:#{port}/working/rails_is_working"
      uri = URI.parse(server_verify_url)

      data = nil
      start_time = Time.now
      last_exception = nil

      while Time.now < (start_time + SERVER_VERIFY_TIMEOUT)
        sleep 0.1
        begin
          data = Net::HTTP.get_response(uri)
          last_exception = nil
        rescue Errno::ECONNREFUSED, EOFError => e
          last_exception = e
        end

        break if data && data.code && data.code.to_s == '200'
      end

      unless data && data.code && data.code.to_s == '200'
        raise_startup_failed_error!(Time.now - start_time, last_exception || "'#{server_verify_url}' returned #{data.code.inspect}, not 200")
      end

      result = data.body.strip

      unless result =~ /^Rails\s+version\s*:\s*(\d+\.\d+\.\d+(\.\d+)?)\s*\n+\s*Ruby\s+version\s*:\s*(\d+\..*?)\s*\n+\s*Ruby\s+engine:\s*(.*?)\s*\n?$/mi
        raise_startup_failed_error!(Time.now - start_time, "'#{server_verify_url}' returned: #{result.inspect}")
      end
      actual_version = $1
      ruby_version = $3
      ruby_engine = $4

      if rails_version != :default && (actual_version != rails_version)
        raise "We seem to have spawned the wrong version of Rails; wanted: #{rails_version.inspect} but got: #{actual_version.inspect}"
      end

      @actual_rails_version = actual_version
      @actual_ruby_version = ruby_version
      @actual_ruby_engine = ruby_engine

      say "Successfully spawned a server running Rails #{actual_version} (Ruby #{ruby_version}, engine #{ruby_engine.inspect}) on port #{port}."
    end

    def is_alive?(pid)
      cmd = "ps -o pid #{pid}"
      results = `#{cmd}`
      results.split(/[\r\n]+/).each do |line|
        line = line.strip.downcase
        next if line == 'pid'
        if line =~ /^\d+$/i
          return true if Integer(line) == pid
        else
          raise "Unexpected output from '#{cmd}': #{results}"
        end
      end

      false
    end

    def stop_server!
      # We do this because under 1.8.7 SIGTERM doesn't seem to work, and it's actually fine to slaughter this
      # process mercilessly -- we don't need anything it has at this point, anyway.
      Process.kill("KILL", server_pid)

      start_time = Time.now

      while true
        if is_alive?(server_pid)
          raise "Unable to kill server at PID #{server_pid}!" if (Time.now - start_time) > 20
          say "Waiting for server at PID #{server_pid} to die."
          sleep 0.1
        else
          break
        end
      end

      say "Successfully terminated Rails server at PID #{server_pid}."

      @server_pid = nil
    end

    class CommandFailedError < StandardError
      attr_reader :directory, :command, :result, :output

      def initialize(directory, command, result, output)
        @directory = directory
        @command = command
        @result = result
        @output = output

        super(%{Command failed: in directory '#{directory}', we tried to run:
% #{command}
but got result: #{result.inspect}
and output:
#{output}})
      end
    end

    def attempt_bundle_install_cmd!(name, use_local)
      cmd = "bundle install"
      cmd << " --local" if use_local

      description = "running 'bundle install' for #{name.inspect}"
      description << " (with remote fetching allowed)" if (! use_local)

      attempts = 0
      while true
        begin
          safe_system(cmd, description)
          break
        rescue CommandFailedError => cfe
          # Sigh. Travis CI sometimes fails this with the following exception:
          #
          # Gem::RemoteFetcher::FetchError: Errno::ETIMEDOUT: Connection timed out - connect(2)
          #
          # So, we catch the command failure, look to see if this is the problem, and, if so, retry
          raise if (! is_travis_remote_fetcher_error?(cfe)) || attempts >= 5
          attempts += 1
        end
      end
    end

    def is_travis_remote_fetcher_error?(command_failed_error)
      command_failed_error.output =~ /Gem::RemoteFetcher::FetchError.*connect/i
    end

    def is_remote_flag_required_error?(command_failed_error)
      command_failed_error.output =~ /could\s+not\s+find.*in\s+the\s+gems\s+available\s+on\s+this\s+machine/mi ||
        command_failed_error.output =~ /could\s+not\s+find.*in\s+any\s+of\s+the.*\s+sources/mi
    end

    def do_bundle_install!(name, allow_remote)
      begin
        attempt_bundle_install_cmd!(name, true)
      rescue CommandFailedError => cfe
        if is_remote_flag_required_error?(cfe) && allow_remote
          attempt_bundle_install_cmd!(name, false)
        else
          raise
        end
      end
    end

    def run_bundle_install!(name)
      @bundle_installs_run ||= { }
      do_bundle_install!(name, ! @bundle_installs_run[name])
      @bundle_installs_run[name] ||= true
    end

    def say(s, newline = true)
      if @verbose
        if newline
          @log.puts s
        else
          @log << s
        end
        @log.flush
      end
    end

    def safe_system(cmd, notice = nil, options = { })
      say("#{notice}...", false) if notice

      total_cmd = if options[:background]
        "#{cmd} 2>&1 &"
      else
        "#{cmd} 2>&1"
      end

      output = `#{total_cmd}`
      raise CommandFailedError.new(Dir.pwd, total_cmd, $?, output) unless $?.success?
      say "OK" if notice

      output
    end


    def is_ruby_18
      !! (RUBY_VERSION =~ /^1\.8\./)
    end

    def is_ruby_1
      !! (RUBY_VERSION =~ /^1\./)
    end

    def is_rails_30
      rails_version && rails_version =~ /^3\.0\./
    end

    def is_rails_31
      rails_version && rails_version =~ /^3\.1\./
    end

    def is_rails_32
      rails_version && rails_version =~ /^3\.2\./
    end

    def backcompat_i18n!(gemfile)
      if is_rails_30
        # Since Rails 3.0.20 was released, a new version of the I18n gem, 0.5.2, was released that moves a constant
        # into a different namespace. (See https://github.com/mislav/will_paginate/issues/347 for more details.)
        # So, if we're running Rails 3.0.x, we lock the 'i18n' gem to an earlier version.
        gemfile.add_version_constraints!('i18n', '= 0.5.0')
      elsif is_ruby_18
        # Since Rails 3.x was released, a new version of the I18n gem, 0.7.0, was released that is incompatible
        # with Ruby 1.8.7. So, if we're running with Ruby 1.8.7, we lock the 'i18n' gem to an earlier version.
        gemfile.add_version_constraints!('i18n', '< 0.7.0')
      end
    end

    def backcompat_rake!(gemfile)
      if is_ruby_18
        # Rake 11 is incompatible with Ruby 1.8
        gemfile.add_version_constraints!('rake', '< 11.0.0')
      end
    end

    def backcompat_rack_cache!(gemfile)
      if is_ruby_1 && (is_rails_31 || is_rails_32)
        # Since Rails 3.1.12 was released, a new version of the rack-cache gem, 1.3.0, was released that requires
        # Ruby 2.0 or above. So, if we're running Rails 3.1.x or 3.2.x on Ruby 1.x, we lock the 'rack-cache' gem
        # to an earlier version.
        gemfile.add_version_constraints!('rack-cache', '< 1.3.0')
      end
    end

    def backcompat_mime_types!(gemfile)
      if is_ruby_1
        # mime-types 3.x depends on mime-types-data, which is not compatible with ruby < 2.x
        gemfile.add_version_constraints!('mime-types', '< 3.0.0')
      end
    end

    def backcompat_execjs!(gemfile)
      if is_ruby_18
        # Apparently execjs released a version 2.2.0 that will happily install on Ruby 1.8.7, but which contains some
        # new-style hash syntax. As a result, we pin the version backwards in this one specific case.
        gemfile.add_version_constraints!('execjs', '~> 2.0.0')
      end
    end

    def backcompat_uglifier!(gemfile)
      # Uglifier 3 is incompatible with Ruby 1.8
      gemfile.add_version_constraints!('uglifier', '< 3.0.0')
    end

    def backcompat_bootstrap_gems!(gemfile)
      backcompat_i18n!(gemfile)
      backcompat_rake!(gemfile)
      backcompat_rack_cache!(gemfile)
      backcompat_mime_types!(gemfile)
    end
  end
end
