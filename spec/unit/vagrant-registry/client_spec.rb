require "spec_helper"
require "yaml"
require "vagrant-registry/client"


describe VagrantPlugins::Registry::Client do
  include_context "vagrant-unit"

  let(:env) { isolated_environment.create_vagrant_env }
  let(:server_url) { "http://foo.com" }

  let(:token_path) { env.data_dir.join("registries_login_tokens.yml") }

  subject { described_class.new(env, server_url) }

  before do
    subject.clear_token
  end

  describe "#logged_in?" do
    let(:url) { %r{^#{server_url}/api/v1/tokens/#{token}/} }
    let(:headers) { { "Content-Type" => "application/json" } }

    before { allow(subject).to receive(:token).and_return(token) }

    context "when there is no token" do
      let(:token) { nil }

      it "returns false" do
        expect(subject.logged_in?).to be(false)
      end
    end

    context "when there is a token" do
      let(:token) { "ABCD1234" }

      it "returns true if the endpoint returns a 200" do
        stub_request(:get, url)
            .with(headers: headers)
            .to_return(body: JSON.pretty_generate("token" => token))
        expect(subject.logged_in?).to be(true)
      end

      it "returns false if the endpoint returns a non-200" do
        stub_request(:get, url)
            .with(headers: headers)
            .to_return(body: JSON.pretty_generate("bad" => true), status: 404)
        expect(subject.logged_in?).to be(false)
      end

      it "raises an exception if the server cannot be found" do
        stub_request(:get, url)
            .to_raise(SocketError)
        expect { subject.logged_in? }
            .to raise_error(VagrantPlugins::Registry::Errors::ServerUnreachable)
      end
    end
  end

  describe "#login" do
    it "returns the access token after successful login" do
      request = {
          "username" => "user",
          "password" => "pass",
      }

      response = {
          "token" => "baz",
      }

      headers = {
          "Accept" => "application/json",
          "Content-Type" => "application/json",
      }

      stub_request(:post, %r{^#{server_url}/api/v1/tokens/}).
          with(body: JSON.dump(request), headers: headers).
          to_return(status: 200, body: JSON.dump(response))

      expect(subject.login("user", "pass")).to eq("baz")
    end

    it "returns nil on bad login" do
      stub_request(:post, %r{^#{server_url}/api/v1/tokens/}).
          to_return(status: 400, body: "")

      expect(subject.login("user", "pass")).to be(false)
    end

    it "raises an exception if it can't reach the sever" do
      stub_request(:post, %r{^#{server_url}/api/v1/tokens/}).
          to_raise(SocketError)

      expect { subject.login("user", "pass") }.
          to raise_error(VagrantPlugins::Registry::Errors::ServerUnreachable)
    end
  end

  describe "#token" do
    it "reads the stored file" do
      subject.store_token("EFGH5678")
      expect(subject.token).to eq("EFGH5678")
    end

    it "returns nil if there's no token set" do
      expect(subject.token).to be(nil)
    end
  end

  describe "#store_token" do
    it "stores the token and can re-access it" do
      subject.store_token("foo")
      expect(subject.token).to eq("foo")
      expect(described_class.new(env, server_url).token).to eq("foo")
    end
  end

  describe "#clear_token" do
    it "deletes the token" do
      subject.store_token("foo")
      subject.clear_token
      expect(subject.token).to be_nil
    end
  end

  describe "#all_tokens" do
    it "returns all stored tokens from file" do
      original = {
          "host1.com" => "token1",
          "some.host2.com" => "token123456",
          "host3" => "token1907",
      }
      File.open(token_path, "w") { |f| f.write(original.to_yaml) }
      expect(subject.all_tokens).to eq(original)
    end

    it "returns empty hash if file with tokens doesn't exist" do
      expect(subject.all_tokens).to eq({})
    end
  end

end
