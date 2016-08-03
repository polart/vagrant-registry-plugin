module VagrantPlugins
  module Registry
    module Command
      class Login < Vagrant.plugin("2", "command")
        def self.synopsis
          "log in to Vagrant registry"
        end

        def execute
          require_relative '../client'

          options = {}

          opts = OptionParser.new do |o|
            o.banner = "Usage: vagrant registry login <url>"
            o.separator ""
            o.on("-c", "--check", "Only checks if you're logged in") do |c|
              options[:check] = c
            end

            o.on("-k", "--logout", "Logs you out if you're logged in") do |k|
              options[:logout] = k
            end

            o.on("-t", "--token TOKEN", String, "Set the registry token") do |t|
              options[:token] = t
            end
          end

          # Parse the options
          argv = parse_options(opts)
          return unless argv

          url = argv[0] || ENV["VAGRANT_REGISTRY_URL"]
          raise Registry::Errors::InvalidURL,
                url: url unless url =~ /\A#{URI::regexp(%w(http https))}\z/

          if !url || argv.length > 1
            raise Vagrant::Errors::CLIInvalidUsage,
                  help: opts.help.chomp
          end

          @client = Client.new(@env, url)

          # Determine what task we're actually taking based on flags
          if options[:check]
            return execute_check
          elsif options[:logout]
            return execute_logout
          elsif options[:token]
            return execute_token(options[:token])
          end

          # Let the user know what is going on.
          @env.ui.output(I18n.t("registry.login.command_header") + "\n")

          @env.ui.output(I18n.t("registry.login.registry_url", :url => url))

          # Ask for the username
          login    = nil
          password = nil
          while !login
            login = @env.ui.ask(I18n.t("registry.login.ask_username") + " ")
          end

          while !password
            password = @env.ui.ask(I18n.t("registry.login.ask_password") + " ",
                                   echo: false)
          end

          token = @client.login(login, password)
          if !token
            @env.ui.error(I18n.t("registry.login.invalid_login"))
            return 1
          end

          @client.store_token(token)
          @env.ui.success(I18n.t("registry.login.logged_in"))
          0
        end

        def execute_check
          if @client.logged_in?
            @env.ui.success(I18n.t("registry.login.check_logged_in"))
            return 0
          else
            @env.ui.error(I18n.t("registry.login.check_not_logged_in"))
            return 1
          end
        end

        def execute_logout
          @client.clear_token
          @env.ui.success(I18n.t("registry.login.logged_out"))
          return 0
        end

        def execute_token(token)
          @client.store_token(token)
          @env.ui.success(I18n.t("registry.login.token_saved"))

          if @client.logged_in?
            @env.ui.success(I18n.t("registry.login.check_logged_in"))
            return 0
          else
            @env.ui.error(I18n.t("registry.login.invalid_token"))
            return 1
          end
        end
      end
    end
  end
end
