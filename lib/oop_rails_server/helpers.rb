require 'active_support'
require 'json'
require 'oop_rails_server/rails_server'

module OopRailsServer
  module Helpers
    extend ActiveSupport::Concern

    attr_reader :rails_server


    def full_path(subpath)
      "#{rails_template_name}/#{subpath}"
    end

    def get(subpath, options = { })
      rails_server.get(full_path(subpath), options)
    end

    def get_response(subpath, options = { })
      rails_server.get_response(full_path(subpath), options)
    end

    def get_success(subpath, options = { })
      data = get(subpath, options)
      expect(data).to match(/oop_rails_server_base_template/i) unless options[:no_layout]
      data
    end

    def expect_match(subpath, *args)
      options = args.extract_options!
      regexes = args

      data = get_success(subpath, options)
      regexes.each do |regex|
        expect(data).to match(regex)
      end

      data
    end

    def expect_exception(subpath, class_name, message)
      data = get(subpath)

      json = begin
        JSON.parse(data)
      rescue => e
        raise %{Expected a JSON response from '#{subpath}' (because we expected an exception),
  but we couldn't parse it as JSON; when we tried, we got:

  (#{e.class.name}) #{e.message}

  The data is:

  #{data.inspect}}
      end

      expect(json['exception']).to be
      expect(json['exception']['class']).to eq(class_name.to_s)
      expect(json['exception']['message']).to match(message)
    end

    def expect_status(subpath, status)
      data = get_response(subpath, ignore_status_code: true)

      expect(data.code.to_i).to eq(status)
    end

    def rails_template_name
      rails_server.name
    end

    def rails_server_project_root
      raise %{You must override #rails_server_project_root in this class (#{self.class.name}) to use OopRailsServer::Helpers;
it should return the fully-qualified path to the root of your project (gem, application, or whatever).}
    end

    def rails_server_templates_root
      @rails_server_templates_root ||= File.join(rails_server_project_root, "spec/rails/templates")
    end

    def rails_server_runtime_base_directory
      @rails_server_runtime_base_directory ||= File.join(rails_server_project_root, "tmp/spec/rails")
    end

    def rails_server_additional_gemfile_lines
      [ ]
    end

    def rails_server_default_version
      nil
    end

    def rails_servers
      @rails_servers ||= { }
    end

    def mail_sent_to(destination_address, the_rails_server = nil)
      the_rails_server ||= rails_server

      mail_file = File.join(mail_directory_for_rails_server(the_rails_server), destination_address)

      if File.exist?(mail_file)
        contents = File.read(mail_file).split(/\n/)
        headers = { }
        last_header = nil
        body = ""
        have_started_body = false

        contents.each do |line|
          if have_started_body
            body << "#{line.chomp}\n"
          elsif line.strip.length == 0
            have_started_body = true
          elsif line =~ /^(\S+):\s+(.*?)\s*$/i
            last_header = $1
            headers[last_header] = $2
          elsif line =~ /^\s+(.*?)\s*$/i && last_header
            headers[last_header] << " #{$1}"
          else
            raise "Unexpected line in #{mail_file.inspect}:\n#{line}"
          end
        end

        { :headers => headers, :body => body }
      else
        if File.exist?(mail_directory_for_rails_server(the_rails_server))
          $stderr.puts "WARNING: No mails for #{destination_address.inspect}: #{Dir.entries(mail_directory_for_rails_server(the_rails_server))}"
        else
          $stderr.puts "WARNING: No mails: no dir: #{mail_directory_for_rails_server(the_rails_server)}"
        end
      end
    end

    def clear_mails!(the_rails_server = nil)
      the_rails_server ||= rails_server

      mail_directory = mail_directory_for_rails_server(the_rails_server)
      entries = Dir.entries(mail_directory).select do |entry|
        entry !~ /^\./ && entry =~ /^\S.*@/
      end

      entries.each { |e| File.delete(File.join(mail_directory, e)) }
    end

    def mail_directory_for_rails_server(the_rails_server = nil)
      the_rails_server ||= rails_server
      File.join(the_rails_server.rails_root, 'tmp', 'mails')
    end

    def rails_server
      if rails_servers.size == 1
        rails_servers[rails_servers.keys.first]
      elsif rails_servers.size == 0
        raise "No Rails servers have been started!"
      else
        raise "Multiple Rails servers have been started; you must specify which one you want: #{rails_servers.keys.join(", ")}"
      end
    end

    def rails_server_implicit_template_paths
      [ ]
    end

    def rails_server_template_paths(template_names)
      template_names.map do |template_name|
        template_name = template_name.to_s
        if template_name =~ %r{^/}
          template_name
        else
          File.join(rails_server_templates_root, template_name)
        end
      end
    end

    def start_rails_server!(options = { })
      templates = Array(options[:templates] || options[:name] || [ ])
      raise "You must specify a template" unless templates.length >= 1

      name = options[:name]
      name ||= templates[0] if templates.length == 1
      name = name.to_s.strip
      raise "You must specify a name" unless name && name.to_s.strip.length > 0

      server = rails_servers[name]
      server ||= begin
        templates =
          rails_server_implicit_template_paths +
          templates

        template_paths = rails_server_template_paths(templates)

        additional_gemfile_lines = Array(rails_server_additional_gemfile_lines || [ ])
        additional_gemfile_lines += Array(options[:additional_gemfile_lines] || [ ])

        server = ::OopRailsServer::RailsServer.new(
          :name => name, :template_paths => template_paths,
          :runtime_base_directory => rails_server_runtime_base_directory,
          :rails_version => (options[:rails_version] || rails_server_default_version),
          :rails_env => options[:rails_env], :additional_gemfile_lines => additional_gemfile_lines)

        rails_servers[name] = server

        server
      end

      server.start!
    end

    def stop_rails_servers!
      exceptions = [ ]
      rails_servers.each do |name, server|
        begin
          server.stop!
        rescue => e
          exceptions << [ name, e ]
        end
      end

      raise "Unable to stop all Rails servers! Got:\n#{exceptions.join("\n")}" if exceptions.length > 0
    end

    module ClassMethods
      def uses_rails_with_template(template_name, options = { })
        before :all do
          start_rails_server!({ :templates => [ template_name ] }.merge(options))
        end

        after :all do
          stop_rails_servers!
        end
      end
    end
  end
end
