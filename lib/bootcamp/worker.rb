require "tempfile"
require "open-uri"
require "zlib"
require "archive/tar/minitar"

# TODO: Abstract everything out of here and clean it up!
module Bootcamp
  
  # Worker is where all the heavy lifting is done
  class Worker < Bootcamp::Depot
    include Archive::Tar
    include Depot::Helpers

    source_root File.dirname(__FILE__)

    desc "new PLUGIN", "creates a new project with the name PLUGIN"
    map "n" => :new
    method_option :library, :aliases => %w(-l), :default => :core, :desc => "LIBRARY options: #{available_frameworks}"
    method_option :test_suite, :aliases => %w(-t), :default => :jasmine, :desc => "TEST_SUITE options: #{available_test_suites}"
    def new(plugin_name)
      @project = plugin_name
      say "Generating #{@project} plugin", :green
      apply manifest("metadata")
      apply manifest("bootstrap")
      apply manifest("html")
      apply manifest(options[:library])
      armory = Armory.new(File.join(Dir.pwd, @project))
    end

    desc "promote [LEVEL]", "give your PLUGIN a promotion updating the verion by patch, minor, or major"
    method_option :grade, :aliases => %w(-g), :default  => :patch, :desc => "GRADE options: patch, minor, major"
    def promote
      ensure_plugin_exists!
      current_ver = project_metadata["version"].split(".").map(&:to_i)
      case options[:grade].to_s.downcase
      when "patch"
        current_ver[2] += 1
      when "minor"
        current_ver[1] += 1
      when "major"
        current_ver[0] += 1
      end
      project_metadata["version"] = current_ver.join(".")

      js = hash_as_pretty_json_string(project_metadata)

      File.open("metadata.json", "w+") do |f|
        f.write(js)
      end
      say("Promoted #{project_metadata["name"]} to #{project_metadata["version"]}", :green)
    end

    desc "compress", "minify the scripts for PLUGIN"
    def compress
      say "Compression not ready yet", :red
    end

    desc "convert", "converts PLUGIN into CoffeeScript"
    def convert
      say "Conversions not ready yet", :red
    end

    desc "package", "packages the plugin into pkg/"
    def package
      ensure_plugin_exists!
      FileUtils.mkdir("pkg") unless Dir.exists?("pkg")
      file_name = "pkg/#{project_metadata["name"]}-#{project_metadata["version"]}.tgz"
      tgz = Zlib::GzipWriter.new(File.open(file_name, "wb"))
      Minitar.pack(`git ls-files`.split("\n"), tgz)

      say("Packaging #{project_metadata["name"]} at #{file_name}", :green)
    end

    desc "deploy", "deploys the PLUGIN to JSHQ.org"
    def deploy
      ensure_plugin_exists!
      connection = Faraday.new(:url => jshq_url)
      res = connection.get do |req|
        req.url("/packages/search?q=#{project_metadata["name"]}")
        req.headers["ACCEPT"] = "application/json,application/vnd.jshq;ver=1"
      end
      packages = JSON.parse(res.body)

      package

      connection = Faraday.new(:url => jshq_url) do |builder|
        builder.use Faraday::Request::NestedMultipart
        builder.request :url_encoded
        builder.request :json
        builder.adapter :net_http
      end

      payload = { :package => {
        :name => project_metadata["name"],
        :summary => project_metadata["summary"],
        :description => project_metadata["description"],
        :versions_attributes  => [{
          :number => project_metadata["version"],
          :authors => project_metadata["authors"],
          :website => project_metadata["website"],
          :documentation => project_metadata["documentation"],
          :packaged_file => Faraday::UploadIO.new("pkg/#{project_metadata["name"]}-#{project_metadata["version"]}.tgz", "application/x-gzip")
        }]
      }}

      if packages.compact.empty?
        res = connection.post do |req|
          req.url("/packages?auth_token=#{authentication_token}")
          req.headers["ACCEPT"] = "application/json,application/vnd.jshq;ver=1"
          req.body = payload
        end

      else
        res = connection.put do |req|
          req.url("/packages/#{packages[0]["slug"]}?auth_token=#{authentication_token}")
          req.headers["ACCEPT"] = "application/json,application/vnd.jshq;ver=1"
          req.body = payload
        end
      end

      say "#{project_metadata["name"]} (#{project_metadata["version"]}) deployed", :green
    end

    desc "search QUERY", "searches jshq.org for QUERY"
    def search(query)
      connection = Faraday.new(:url => jshq_url)
      res = connection.get do |req|
        req.url("/packages/search?q=#{query}")
        req.headers["ACCEPT"] = "application/json,application/vnd.jshq;ver=1"
      end

      packages = JSON.parse(res.body)

      say("No plugins where found for '#{query}'", :red) if packages.empty?

      packages.each do |package|
        versions = package["versions"].collect { |v| v["number"] }.join(", ")
        say("#{package["name"]} (#{versions})")
      end
    end

    desc "install PLUGIN", "installs PLUGIN from jsqh.org"
    method_option :version, :aliases => %w(-v), :desc => "VERSION of the plugin to install"
    def install(plugin)
      connection = Faraday.new(:url => jshq_url)
      res = connection.get do |req|
        req.url("/packages/search?q=#{plugin}")
        req.headers["ACCEPT"] = "application/json,application/vnd.jshq;ver=1"
      end

      package = JSON.parse(res.body).first

      res = connection.get do |req|
        url = "/packages/#{package["slug"]}/download"
        url += "?version=#{version}" if version
        req.url(url)
        req.headers["ACCEPT"] = "application/json,application/vnd.jshq;ver=1"
      end

      url = JSON.parse(res.body)["url"]
      Minitar.unpack(Zlib::GzipReader.new(open(url)), ".")

      say "#{plugin} installed", :green
    end

    desc "-v | --version", "displays the bootcamp version"
    map %w(-v --version) => :version
    def version
      say("Bootcamp v.#{Bootcamp::VERSION}")
    end
  end
end
