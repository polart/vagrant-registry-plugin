require "spec_helper"
require "yaml"
require "vagrant-registry/command/login"


describe VagrantPlugins::Registry::Command::Login do
  include_context "vagrant-unit"

  let(:env) { isolated_environment.create_vagrant_env }
  let(:server_url) { "http://foo.com" }
  let(:server_host) { "foo.com" }

  let(:token_path) { env.data_dir.join("registries_login_tokens.yml") }

  subject { described_class.new(argv, env) }

  before do
    ENV["VAGRANT_REGISTRY_URL"] = server_url
  end

  describe "#execute" do

    context "with --check" do
      let(:token) { "asdf1234" }
      let(:argv) { ["--check"] }

      context "when there is a token" do
        before do
          stub_request(:get, %r{^#{server_url}/api/v1/tokens/#{token}/})
              .to_return(status: 200)
        end

        before do
          File.open(token_path, "w") do |file|
            file.write({ server_host => token }.to_yaml)
          end
        end

        it "returns 0" do
          expect(subject.execute).to eq(0)
        end
      end

      context "when there is no token" do
        it "returns 1" do
          expect(subject.execute).to eq(1)
        end
      end

    end

    context "with --logout" do
      let(:argv) { ["--logout"] }

      it "returns 0" do
        expect(subject.execute).to eq(0)
      end

      it "clears the token" do
        subject.execute
        expect(File.exist?(token_path)).to be(false)
      end
    end

    context "with --token" do
      let(:token) { "qwer1234" }
      let(:argv) { ["--token", token] }

      context "when the token is valid" do
        before do
          stub_request(:get, %r{^#{server_url}/api/v1/tokens/#{token}/})
              .to_return(status: 200)
        end

        it "sets the token" do
          subject.execute
          token = YAML::load_file(token_path)[server_host]
          expect(token).to eq(token)
        end

        it "returns 0" do
          expect(subject.execute).to eq(0)
        end
      end

      context "when the token is invalid" do
        before do
          stub_request(:get, %r{^#{server_url}/api/v1/tokens/#{token}/})
              .to_return(status: 404)
        end

        it "returns 1" do
          expect(subject.execute).to eq(1)
        end
      end
    end

    context "with URL in argv and in environment variable" do
      let(:token) { "qwer1234" }
      let(:argv) { ["--check", "http://bar.com"] }

      before do
        File.open(token_path, "w") do |file|
          file.write({ server_host => token }.to_yaml)
        end
      end

      it "prefers URL from argv" do
        expect(subject.execute).to eq(1)
      end
    end

    context "with invalid URL" do
      let(:argv) { ["http@//bar.com"] }

      it "shows error message" do
        expect { subject.execute }
            .to raise_error(VagrantPlugins::Registry::Errors::InvalidURL)
      end
    end

    context "with more than one arguments" do
      let(:argv) { ["one", "two"] }

      it "shows help" do
        expect { subject.execute }.
            to raise_error(Vagrant::Errors::CLIInvalidUsage)
      end
    end

    context "with no arguments and no environment variable" do
      let(:argv) { [] }

      before do
        ENV["VAGRANT_REGISTRY_URL"] = nil
      end

      it "shows help" do
        expect { subject.execute }.
            to raise_error(Vagrant::Errors::CLIInvalidUsage)
      end
    end

  end

end
