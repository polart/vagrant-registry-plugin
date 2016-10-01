require "yaml"
require "uri"
require "rest_client"
require "vagrant/util/downloader"
require "ruby-progressbar"

require_relative "errors"

module VagrantPlugins
  module Registry
    class Uploader

      # Initializes a box uploader
      #
      # @param [Vagrant::Environment] env
      # @param [String] path
      # @param [String] url
      # @param [String] version
      # @param [String] provider
      def initialize(env, path, url, version, provider,
                     chunk_size = 1024 * 1024 * 5) # 5 MB
        @logger = Log4r::Logger.new("vagrant::registry::uploader")
        @env = env
        @path = path
        @version = version
        @provider = provider
        @chunk_size = chunk_size
        @file_size = Pathname.new(path).size?
        @box_file_hash = Digest::SHA256.file(@path).hexdigest

        u = URI.parse(url)
        _, @username, @box_name = u.path.split("/")
        u.path, u.opaque, u.query, u.fragment = ""
        @root_url = u.to_s

        @interrupted_upload_url = self.interrupted_upload_url

        # Set global proxy for all requests
        proxy = nil
        proxy ||= ENV["HTTPS_PROXY"] || ENV["https_proxy"]
        proxy ||= ENV["HTTP_PROXY"]  || ENV["http_proxy"]
        RestClient.proxy = proxy
      end

      # Upload new box
      def upload_box
        if @interrupted_upload_url
          @logger.info("Continuing box upload '#{@path}' #{@version} " \
                       "#{@provider} to '#{@interrupted_upload_url}'")
          upload_url = @interrupted_upload_url
          @env.ui.info(I18n.t("vagrant_registry.push.continue_upload"))
        else
          @logger.info("Uploading new box '#{@path}' #{@version} " \
                       "#{@provider} to '#{@root_url}'")
          begin
            upload_url = self.initiate_upload
          rescue RestClient::ResourceNotFound
            self.create_new_box
            upload_url = self.initiate_upload
          end
        end

        self.upload_box_file(upload_url)
      end

      # Upload new box without continuing previously interrupted upload
      def upload_box!
        self.clean_stored_upload_url
        self.upload_box
      end

      protected

      # Initiate a box upload
      #
      # @return [String] URL to which box file should be uploaded
      def initiate_upload
        @logger.debug("Initiating upload for box '#{@path}'")
        api_url = URI.join(@root_url, "/api/boxes/#{@username}/#{@box_name}/uploads/").to_s
        url = self.authenticate_url(api_url)

        with_error_handling do
          payload = {
              :file_size => @file_size,
              :checksum_type => "sha256",
              :checksum => @box_file_hash,
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
          upload_url = JSON.load(response.to_s)["url"]
          self.store_upload_url(upload_url)
          return upload_url
        end

      end

      # Create new user box
      def create_new_box
        @logger.info("Creating new box #{@username}/#{@box_name}")
        create_box = nil
        message = I18n.t("vagrant_registry.push.ask_box_create",
                         :username => @username,
                         :box_name => @box_name) + " "
        until create_box == "y" || create_box == "n"
          create_box = @env.ui.ask(message)
          create_box.downcase!
        end

        if create_box == "n"
          raise Registry::Errors::BoxUploadTerminatedByUser
        end

        api_url = URI.join(@root_url, "/api/boxes/#{@username}/").to_s
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

        @env.ui.success(I18n.t("vagrant_registry.push.box_created",
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
            chunk = f.read(@chunk_size)
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
                  self.clean_stored_upload_url
                  @env.ui.success(I18n.t("vagrant_registry.push.box_file_uploaded"))
                end
              rescue RestClient::BadRequest => e
                @env.ui.info("")  # move away from progress bar line
                raise e
              rescue RestClient::ResourceNotFound
                raise Registry::Errors::BoxUploadExpired
              rescue RestClient::RequestedRangeNotSatisfiable => e
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

      def interrupted_upload_url
        self.all_interrupted_uploads[self.upload_hash]
      end

      # Store upload URL that later can be used to resume interrupted upload.
      def store_upload_url(url)
        @logger.debug("Storing upload URL #{url} in #{interrupted_uploads_path}")
        uploads = all_interrupted_uploads
        uploads[upload_hash] = url
        File.open(interrupted_uploads_path, "w") do |file|
          file.write uploads.to_yaml
        end
      end

      def clean_stored_upload_url
        @logger.debug("Clearing upload URL for box hash #{@box_file_hash}")
        uploads = all_interrupted_uploads
        uploads.delete(upload_hash)
        File.open(interrupted_uploads_path, "w") do |file|
          file.write uploads.to_yaml
        end
        @interrupted_upload_url = nil
      end

      def upload_hash
        Digest::SHA256.hexdigest "#{@root_url}-#{@box_file_hash}-#{@version}-#{@provider}"
      end

      # Reads all stored interrupted uploads for all registries.
      #
      # @return [Hash] hash => Registry URL
      def all_interrupted_uploads
        if interrupted_uploads_path.exist?
          return YAML::load_file(interrupted_uploads_path)
        end

        {}
      end

      def interrupted_uploads_path
        @env.data_dir.join("registries_uploads.yml")
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
        raise Errors::ServerUnreachable, url: @root_url
      end

    end
  end
end
