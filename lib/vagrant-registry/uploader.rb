require "yaml"
require "uri"
require "rest_client"
require "vagrant/util/downloader"
require "vagrant/util/presence"
require "ruby-progressbar"

require_relative "errors"

module VagrantPlugins
  module Registry
    class Uploader

      CHUNK_SIZE = 1024 * 1024 * 5  # 5 MB

      # Initializes a box uploader
      #
      # @param [Vagrant::Environment] env
      # @param [String] path
      # @param [String] url
      # @param [String] version
      # @param [String] provider
      def initialize(env, path, url, version, provider)
        @logger = Log4r::Logger.new("vagrant::registry::uploader")
        @env = env
        @path = path
        @version = version
        @provider = provider
        @file_size = Pathname.new(path).size?

        u = URI.parse(url)
        _, @username, @box_name = u.path.split("/")
        u.path, u.opaque, u.query, u.fragment = ""
        @url = u.to_s

        # Set global proxy for all requests
        proxy = nil
        proxy ||= ENV["HTTPS_PROXY"] || ENV["https_proxy"]
        proxy ||= ENV["HTTP_PROXY"]  || ENV["http_proxy"]
        RestClient.proxy = proxy
      end

      # Upload new box
      def upload_box
        @logger.info("Uploading box '#{@path}' #{@version} #{@provider} to '#{@url}'")
        begin
          upload_url = self.initiate_upload
        rescue RestClient::NotFound
          self.create_new_box
          upload_url = self.initiate_upload
        end

        self.upload_box_file(upload_url)
      end

      protected

      # Initiate a box upload
      #
      # @return [String] URL to which box file should be uploaded
      def initiate_upload
        @logger.debug("Initiating upload for box '#{@path}'")
        api_url = URI.join(@url, "/api/boxes/#{@username}/#{@box_name}/uploads/").to_s
        url = self.authenticate_url(api_url)

        with_error_handling do
          payload = {
              :file_size => @file_size,
              :checksum_type => 'sha256',
              :checksum => Digest::SHA256.file(@path).to_s,
              :version => @version,
              :provider =>@provider,
          }
          response = RestClient::Request.execute(
              method: :post,
              url: url,
              payload: JSON.dump(payload),
              headers: {
                  accept: :json,
                  content_type: :json,
                  user_agent: Vagrant::Util::Downloader::USER_AGENT,
              },
          )
          return JSON.load(response.to_s)['url']
        end

      end

      # Create new user box
      def create_new_box
        @logger.info("Creating new box #{@username}/#{@box_name}")
        create_box = nil
        message = I18n.t("registry.push.ask_box_create",
                         :username => @username,
                         :box_name => @box_name) + " "
        until create_box == "y" || create_box == "n"
          create_box = @env.ui.ask(message)
          create_box.downcase!
        end

        if create_box == "n"
          raise Registry::Errors::BoxUploadTerminatedByUser
        end

        api_url = URI.join(@url, "/api/boxes/#{@username}/").to_s
        url = self.authenticate_url(api_url)

        with_error_handling do
          payload = {:name => @box_name}
          RestClient::Request.execute(
              method: :post,
              url: url,
              payload: JSON.dump(payload),
              headers: {
                  accept: :json,
                  content_type: :json,
                  user_agent: Vagrant::Util::Downloader::USER_AGENT,
              },
          )
        end

        @env.ui.success(I18n.t("registry.push.box_created",
                               :username => @username,
                               :box_name => @box_name))
      end

      # Upload box file
      #
      # @param [String] url to which box file should be uploaded
      def upload_box_file(url)
        @logger.debug("Uploading box file '#{@path}' to '#{url}'")

        url = self.authenticate_url(url)

        progressbar = ProgressBar.create(
            :total => @file_size / 1024 / 1024,   # megabytes
            :format => "Uploading: [%b>%i] %c MB/%C MB | %R MB/sec |%e")

        File.open(@path, "rb") do |f|
          until f.eof?
            offset_start = f.pos
            chunk = f.read(CHUNK_SIZE)
            content_range = "bytes #{offset_start}-#{f.pos}/#{@file_size}"

            with_error_handling do
              begin
                response = RestClient::Request.execute(
                    method: :put,
                    url: url,
                    payload: chunk,
                    headers: {
                        accept: :json,
                        content_type: "application/octet-stream",
                        content_range: content_range,
                        user_agent: Vagrant::Util::Downloader::USER_AGENT,
                    },
                )

                progressbar.progress = f.pos / 1024 / 1024  # megabytes

                if response.code == 201
                  @env.ui.success(I18n.t("registry.push.box_file_uploaded"))
                end
              rescue RestClient::BadRequest => e
                @env.ui.info("")  # move away from progress bar line
                raise e
              rescue RestClient::NotFound
                raise Registry::Errors::BoxUploadExpired
              rescue RestClient::RangeNotSatisfiable => e
                @logger.debug("Range not satisfiable")

                begin
                  offset = JSON.parse(e.response)["offset"]
                  f.pos = offset
                rescue JSON::ParserError
                  @env.ui.info("")  # move away from progress bar line
                  raise "An unexpected error occurred: #{e.inspect}"
                end
              end
            end
          end
        end
      end

      def authenticate_url(url)
        hook_env = @env.hook(:authenticate_box_url, box_urls: [url])
        authed_urls = hook_env[:box_urls]
        if !authed_urls || authed_urls.length != 1
          raise "Bad box authentication hook, did not generate proper results."
        end
        authed_urls[0]
      end

      def with_error_handling(&block)
        yield
      rescue RestClient::BadRequest => e
        begin
          response = JSON.parse(e.response)
          detail = response["detail"]
          message = !detail.nil? ? "#{detail}\n" : ""
          response.each do |key, value|
            if value.is_a? Array
              value = value.join(' | ')
            end
            message += " * #{key}: #{value}\n"
          end
          raise Registry::Errors::BoxUploadError, message: message
        rescue JSON::ParserError
          raise "An unexpected error occurred: #{e.inspect}"
        end
      rescue RestClient::Unauthorized
        raise Registry::Errors::NotLoggedIn
      rescue RestClient::Forbidden
        raise Errors::PermissionDenied
      rescue SocketError
        raise Errors::ServerUnreachable, url: @url
      end

    end
  end
end
