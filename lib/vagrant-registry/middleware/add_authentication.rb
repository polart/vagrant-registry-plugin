require "cgi"
require "uri"

require_relative "../client"

# Based on VagrantPlugins::LoginCommand::AddAuthentication

module VagrantPlugins
  module Registry
    class AddAuthentication

      def initialize(app, env)
        @app = app
        @logger = Log4r::Logger.new("vagrant::registry::add_authentication")
      end

      def call(env)
        tokens = Client.new(env[:env], nil).all_tokens

        @logger.info("\n\n\n==> VAGRANT-REGISTRY \n\n\n")
        @logger.info("==> tokens: #{tokens}")

        unless tokens.empty?
          env[:box_urls].map! do |url|
            @logger.info("==> url: #{url}")

            u = URI.parse(url)
            @logger.info("==> u: #{u}")

            token = tokens[u.host]
  
            @logger.info("==> token: #{token}")

            unless token.nil?
              q = CGI.parse(u.query || "")

              @logger.info("==> q: #{q}")

              current = q["auth_token"]
              if current && current.empty?
                q["auth_token"] = token
              end

              u.query = URI.encode_www_form(q)

              @logger.info("==> u: #{u}")
            end

            u.to_s
          end
        end

        @app.call(env)
      end
    end
  end
end
