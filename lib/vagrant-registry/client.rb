require "yaml"
require "uri"
require "rest_client"
require "vagrant/util/downloader"
require "vagrant/util/presence"
require_relative "errors"

module VagrantPlugins
  module Registry
    class Client
      include Vagrant::Util::Presence

      # Initializes a login client with the given Vagrant::Environment.
      #
      # @param [Vagrant::Environment] env url
      def initialize(env, url)
        @logger = Log4r::Logger.new("vagrant::registry::client")
        @env    = env
        @url    = url
        @host   = @url.nil? ? nil : URI.parse(@url).host
      end

      # Removes the token, effectively logging the user out.
      def clear_token
        @logger.info("Clearing token for registry #{@url}")
        if token_path.file?
          tokens = self.all_tokens
          tokens.delete(@host)
          File.open(token_path, "w") do |file|
            file.write tokens.to_yaml
          end
        end
      end

      # Checks if the user is logged in by verifying their authentication
      # token.
      #
      # @return [Boolean]
      def logged_in?
        token = self.token
        return false if !token

        with_error_handling do
          url = URI.join(@url, "/api-token-auth/#{token}/").to_s
          RestClient.get(url, content_type: :json)
          true
        end
      end

      # Login logs a user in and returns the token for that user. The token
      # is _not_ stored unless {#store_token} is called.
      #
      # @param [String] user
      # @param [String] pass
      # @return [String] token The access token, or nil if auth failed.
      def login(user, pass)
        @logger.info("Logging in '#{user}' into registry #{@url}")

        with_error_handling do
          url      = URI.join(@url, "/api-token-auth/").to_s
          request  = { "username" => user, "password" => pass }

          proxy   = nil
          proxy ||= ENV["HTTPS_PROXY"] || ENV["https_proxy"]
          proxy ||= ENV["HTTP_PROXY"]  || ENV["http_proxy"]
          RestClient.proxy = proxy

          response = RestClient::Request.execute(
              method: :post,
              url: url,
              payload: JSON.dump(request),
              proxy: proxy,
              headers: {
                  accept: :json,
                  content_type: :json,
                  user_agent: Vagrant::Util::Downloader::USER_AGENT,
              },
          )

          data = JSON.load(response.to_s)
          data["token"]
        end
      end

      # Stores the given token locally, removing any previous tokens.
      #
      # @param [String] token
      def store_token(token)
        @logger.info("Storing token for registry #{@url} in #{token_path}")

        tokens = self.all_tokens
        tokens[@host] = token
        File.open(token_path, "w") do |file|
          file.write tokens.to_yaml
        end

        nil
      end

      # Reads the access token if there is one. This will first read the
      # `ATLAS_TOKEN` environment variable and then fallback to the stored
      # access token on disk.
      #
      # @return [String]
      def token
        token = self.all_tokens[@host]
        if token
          @logger.debug("Using authentication token from #{token_path} for" \
                        " registry #{@url}")
          return token
        end

        @logger.debug("No authentication token in #{token_path} for" \
                      " registry #{@url}")

        nil
      end

      def all_tokens
        if token_path.exist?
          return YAML::load_file(token_path)
        end

        {}
      end

      protected

      def with_error_handling(&block)
        yield
      rescue RestClient::Unauthorized
        @logger.debug("Unauthorized!")
        false
      rescue RestClient::NotAcceptable => e
        @logger.debug("Got unacceptable response:")
        @logger.debug(e.message)
        @logger.debug(e.backtrace.join("\n"))

        begin
          errors = JSON.parse(e.response)["errors"].join("\n")
          raise Errors::ServerError, errors: errors
        rescue JSON::ParserError; end

        raise "An unexpected error occurred: #{e.inspect}"
      rescue RestClient::BadRequest
        false
      rescue RestClient::NotFound
        false
      rescue SocketError
        @logger.info("Socket error")
        raise Errors::ServerUnreachable, url: @url
      end

      def token_path
        @env.data_dir.join("registries_login_tokens.yml")
      end
    end
  end
end
