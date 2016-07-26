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
        Command::Root
      end

    end
  end
end
