require "simplecov"
SimpleCov.start

require "rubygems"
require "vagrant-spec/unit"
require "webmock/rspec"

$LOAD_PATH.unshift File.expand_path("../lib", __FILE__)
require "vagrant-registry"

RSpec.configure do |config|
  config.order = "random"
end
