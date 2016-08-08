require "spec_helper"
require "yaml"
require "vagrant-registry/command/push"


describe VagrantPlugins::Registry::Command::Push do
  include_context "vagrant-unit"

  let(:env) { isolated_environment.create_vagrant_env }
  let(:server_url) { "http://foo.com" }

  subject { described_class.new(argv, env) }

  let(:uploader) { double("uploader") }
  let(:client) { VagrantPlugins::Registry::Client.new(env, server_url) }

  before do
    ENV["VAGRANT_REGISTRY_URL"] = server_url
  end

  describe "#execute" do

    context "with more than four arguments" do
      let(:argv) { ["one", "two", "three", "four", "five"] }

      it "shows help" do
        expect { subject.execute }.
            to raise_error(Vagrant::Errors::CLIInvalidUsage)
      end
    end

    context "with less than four arguments" do
      let(:argv) { ["one", "two", "three"] }

      it "shows help" do
        expect { subject.execute }.
            to raise_error(Vagrant::Errors::CLIInvalidUsage)
      end
    end

    context "with invalid URL" do
      let(:argv) { ["test.box", "http@//bar.com", "0.1.0", "virtualbox"] }

      it "shows error message" do
        expect { subject.execute }
            .to raise_error(VagrantPlugins::Registry::Errors::InvalidURL)
      end
    end

    context "with box name instead of URL" do
      let(:box_file) { temporary_file }
      let(:argv) { [box_file.to_s, "user/box", "0.1.0", "virtualbox"] }

      context "when environment variable is set" do
        before do
          allow(subject).to receive(:logged_in?)
        end

        it "constructs valid URL" do
          expect(VagrantPlugins::Registry::Uploader).to receive(:new).with(
              env,
              box_file.to_s,
              "#{server_url}/user/box",
              "0.1.0",
              "virtualbox"
          ).and_return(uploader)
          expect(uploader).to receive(:upload_box)

          subject.execute
        end
      end

      context "when environment variable not set" do
        before do
          ENV["VAGRANT_REGISTRY_URL"] = nil
        end

        it "shows help" do
          expect { subject.execute }
              .to raise_error(Vagrant::Errors::CLIInvalidUsage)
        end
      end
    end

    context "with --new-upload" do
      let(:box_file) { temporary_file }
      let(:argv) { [box_file.to_s, "user/box", "0.1.0",
                    "virtualbox", "--new-upload"] }

      before do
        allow(subject).to receive(:logged_in?)
      end

      it "uploads box without resuming interrupted upload" do
        expect(VagrantPlugins::Registry::Uploader).to receive(:new).with(
            env,
            box_file.to_s,
            "#{server_url}/user/box",
            "0.1.0",
            "virtualbox"
        ).and_return(uploader)
        expect(uploader).to receive(:upload_box!)

        subject.execute
      end
    end

    context "when user not logged in" do
      let(:box_file) { temporary_file }
      let(:argv) { [box_file.to_s, "user/box", "0.1.0", "virtualbox"] }

      before do
        client = double(VagrantPlugins::Registry::Client)
        allow(VagrantPlugins::Registry::Client)
            .to receive(:new).and_return(client)
        allow(client).to receive(:logged_in?).and_return(false)
      end

      it "shows error message" do
        expect { subject.execute }
            .to raise_error(VagrantPlugins::Registry::Errors::NotLoggedIn)
      end
    end

  end

end
