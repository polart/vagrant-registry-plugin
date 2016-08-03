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
          raise Registry::Errors::InvalidURL unless
              url =~ /\A#{URI::regexp(%w(http https))}\z/

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
          @env.ui.output(I18n.t("login_command.command_header") + "\n")

          @env.ui.output("Registry URL: #{url}")

          # Ask for the username
          login    = nil
          password = nil
          while !login
            login = @env.ui.ask("Registry Username: ")
          end

          while !password
            password = @env.ui.ask("Password (will be hidden): ", echo: false)
          end

          token = @client.login(login, password)
          if !token
            @env.ui.error(I18n.t("login_command.invalid_login"))
            return 1
          end

          @client.store_token(token)
          @env.ui.success(I18n.t("login_command.logged_in"))
          0
        end

        def execute_check
          if @client.logged_in?
            @env.ui.success(I18n.t("login_command.check_logged_in"))
            return 0
          else
            @env.ui.error(I18n.t("login_command.check_not_logged_in"))
            return 1
          end
        end

        def execute_logout
          @client.clear_token
          @env.ui.success(I18n.t("login_command.logged_out"))
          return 0
        end

        def execute_token(token)
          @client.store_token(token)
          @env.ui.success(I18n.t("login_command.token_saved"))

          if @client.logged_in?
            @env.ui.success(I18n.t("login_command.check_logged_in"))
            return 0
          else
            @env.ui.error(I18n.t("login_command.invalid_token"))
            return 1
          end
        end
      end
    end
  end
end
