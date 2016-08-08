require "spec_helper"
require "vagrant-registry/middleware/add_authentication"


describe VagrantPlugins::Registry::AddAuthentication do
  include_context "vagrant-unit"

  let(:app) { lambda { |env| } }
  let(:env) { {
      env: iso_env,
  } }

  let(:iso_env) { isolated_environment.create_vagrant_env }
  let(:server_url) { "http://foo.com" }

  subject { described_class.new(app, env) }

  describe "#call" do
    it "does nothing if we aren't logged in" do
      original = ["foo", "#{server_url}/bar"]
      env[:box_urls] = original.dup

      subject.call(env)

      expect(env[:box_urls]).to eq(original)
    end

    it "appends the access token to the URL of server URLs" do
      token = "asdf1234"
      VagrantPlugins::Registry::Client.new(iso_env, server_url).store_token(token)

      original = [
          "http://google.com/box.box",
          "#{server_url}/foo.box",
          "#{server_url}/bar.box?arg=true",
      ]

      expected = original.dup
      expected[1] = "#{original[1]}?auth_token=#{token}"
      expected[2] = "#{original[2]}&auth_token=#{token}"

      env[:box_urls] = original.dup
      subject.call(env)

      expect(env[:box_urls]).to eq(expected)
    end

    it "does not append multiple access_tokens" do
      token = "asdf1234"
      VagrantPlugins::Registry::Client.new(iso_env, server_url).store_token(token)

      original = [
          "#{server_url}/foo.box?auth_token=existing",
          "#{server_url}/bar.box?arg=true",
      ]

      env[:box_urls] = original.dup
      subject.call(env)

      expect(env[:box_urls][0]).to eq("#{original[0]}")
      expect(env[:box_urls][1]).to eq("#{original[1]}&auth_token=#{token}")
    end
  end

end
