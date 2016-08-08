require "cgi"
require "uri"

require_relative "../client"

# Based on VagrantPlugins::LoginCommand::AddAuthentication

module VagrantPlugins
  module Registry
    class AddAuthentication

      def initialize(app, env)
        @app = app
      end

      def call(env)
        tokens = Client.new(env[:env], nil).all_tokens

        unless tokens.empty?
          env[:box_urls].map! do |url|
            u = URI.parse(url)
            token = tokens[u.host]

            unless token.nil?
              q = CGI.parse(u.query || "")

              current = q["auth_token"]
              if current && current.empty?
                q["auth_token"] = token
              end

              u.query = URI.encode_www_form(q)
            end

            u.to_s
          end
        end

        @app.call(env)
      end
    end
  end
end
