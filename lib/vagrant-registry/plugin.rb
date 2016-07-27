begin
  require "vagrant"
rescue LoadError
  raise "The vagrant-registry plugin must be run within Vagrant."
end

module VagrantPlugins
  module Registry
    class Plugin < Vagrant.plugin("2")
      name "registry"
      description <<-DESC
      This plugin allows integration with private box registries.
      DESC

      command("registry") do
        require File.expand_path("../command/root", __FILE__)
        init!
        Command::Root
      end

      protected

      def self.init!
        return if defined?(@_init)
        I18n.load_path << File.expand_path("../locales/en.yml", __FILE__)
        I18n.reload!
        @_init = true
      end

    end
  end
end
