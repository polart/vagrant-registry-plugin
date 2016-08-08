begin
  require "vagrant"
rescue LoadError
  raise "The vagrant-registry plugin must be run within Vagrant."
end

require_relative "vagrant-registry/plugin"
require_relative "vagrant-registry/version"
require_relative "vagrant-registry/errors"

module VagrantPlugins
  module Registry
    I18n.load_path << File.expand_path("../../locales/en.yml", __FILE__)
    I18n.reload!
  end
end
