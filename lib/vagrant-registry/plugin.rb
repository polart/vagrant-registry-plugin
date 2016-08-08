module VagrantPlugins
  module Registry
    class Plugin < Vagrant.plugin("2")
      name "registry"
      description <<-DESC
      This plugin allows integration with private box registries.
      DESC

      command("registry") do
        require_relative "command/root"
        init!
        Command::Root
      end

      action_hook(:registry_authenticated_boxes, :authenticate_box_url) do |hook|
        require_relative "middleware/add_authentication"
        hook.prepend(AddAuthentication)
      end

      protected

      def self.init!
        return if defined?(@_init)
        @_init = true
      end

    end
  end
end
