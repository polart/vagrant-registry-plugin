require "spec_helper"
require "yaml"
require "vagrant-registry/uploader"


describe VagrantPlugins::Registry::Uploader do
  include_context "vagrant-unit"

  let(:env) { isolated_environment.create_vagrant_env }
  let(:server_url) { "http://foo.com" }
  let(:box_file) { temporary_file("box content 123") }

  let(:token_path) { env.data_dir.join("registries_login_tokens.yml") }

  subject { described_class.new(env,
                                box_file.to_s,
                                "#{server_url}/user/box",
                                "0.1.0",
                                "virtualbox") }

  before do
    # Stub progress bar entirely
    allow(ProgressBar).to receive(:create).
        and_return(double(ProgressBar).as_null_object)
  end

  describe "#upload_box" do

    it "can upload file in chunks" do
      uploader =described_class.new(env,
                                    box_file.to_s,
                                    "#{server_url}/user/box",
                                    "0.1.0",
                                    "virtualbox",
                                    chunk_size = 5)

      upload_url = "#{server_url}/api/boxes/user/box/uploads/123/"
      initiate_response = {
          "url" => upload_url,
      }
      initiate_stub = stub_request(:post, "#{server_url}/api/boxes/user/box/uploads/").
          to_return(status: 200, body: JSON.dump(initiate_response))

      upload_request_p1 = "box c"
      upload_headers_p1 = {
          "Accept" => "application/json",
          "Content-Type" => "application/octet-stream",
          "Content-Range" => "bytes 0-5/#{box_file.size}",
      }
      upload_request_p2 = "onten"
      upload_headers_p2 = {
          "Accept" => "application/json",
          "Content-Type" => "application/octet-stream",
          "Content-Range" => "bytes 5-10/#{box_file.size}",
      }
      upload_request_p3 = "t 123"
      upload_headers_p3 = {
          "Accept" => "application/json",
          "Content-Type" => "application/octet-stream",
          "Content-Range" => "bytes 10-#{box_file.size}/#{box_file.size}",
      }
      upload_stub = stub_request(:put, upload_url).
          with(body: upload_request_p1, headers: upload_headers_p1).
          to_return(status: 202)
      upload_stub2 = stub_request(:put, upload_url).
          with(body: upload_request_p2, headers: upload_headers_p2).
          to_return(status: 202)
      upload_stub3 = stub_request(:put, upload_url).
          with(body: upload_request_p3, headers: upload_headers_p3).
          to_return(status: 201)

      uploader.upload_box

      expect(initiate_stub).to have_been_requested.times(1)
      expect(upload_stub).to have_been_requested.times(1)
      expect(upload_stub2).to have_been_requested.times(1)
      expect(upload_stub3).to have_been_requested.times(1)
    end

    context "when specified box exists in registry" do
      it "uploads file to existing box" do
        upload_url = "#{server_url}/api/boxes/user/box/uploads/123/"
        initiate_request = {
            "file_size" => box_file.size,
            "checksum_type" => "sha256",
            "checksum" => Digest::SHA256.file(box_file).hexdigest,
            "version" => "0.1.0",
            "provider" => "virtualbox",
        }
        initiate_response = {
            "url" => upload_url,
        }
        initiate_headers = {
            "Accept" => "application/json",
            "Content-Type" => "application/json",
        }
        initiate_stub = stub_request(:post, "#{server_url}/api/boxes/user/box/uploads/").
            with(body: JSON.dump(initiate_request), headers: initiate_headers).
            to_return(status: 200, body: JSON.dump(initiate_response))

        upload_request = "box content 123"
        upload_headers = {
            "Accept" => "application/json",
            "Content-Type" => "application/octet-stream",
            "Content-Range" => "bytes 0-#{box_file.size}/#{box_file.size}",
        }
        upload_stub = stub_request(:put, upload_url).
            with(body: upload_request, headers: upload_headers).
            to_return(status: 201)

        subject.upload_box

        expect(initiate_stub).to have_been_requested.times(1)
        expect(upload_stub).to have_been_requested.times(1)
      end
    end

    context "when specified box doesn't exist in registry" do
      it "at first creates the box and then uploads file" do
        allow(env.ui).to receive(:ask).and_return("y")

        upload_url = "#{server_url}/api/boxes/user/box/uploads/123/"
        initiate_response = {
            "url" => upload_url,
        }
        initiate_stub = stub_request(:post, "#{server_url}/api/boxes/user/box/uploads/").
            to_return(status: 404).then.
            to_return(status: 200, body: JSON.dump(initiate_response))

        new_box_request = {
            "name" => "box",
        }
        new_box_headers = {
            "Accept" => "application/json",
            "Content-Type" => "application/json",
        }
        new_box_stub = stub_request(:post, "#{server_url}/api/boxes/user/").
            with(body: JSON.dump(new_box_request), headers: new_box_headers).
            to_return(status: 200)

        upload_stub = stub_request(:put, upload_url).
            to_return(status: 201)

        subject.upload_box

        expect(initiate_stub).to have_been_requested.times(2)
        expect(new_box_stub).to have_been_requested.times(1)
        expect(upload_stub).to have_been_requested.times(1)
      end
    end

    context "when upload URL expired" do
      it "shows error message" do
        upload_url = "#{server_url}/api/boxes/user/box/uploads/123/"
        initiate_response = {
            "url" => upload_url,
        }
        initiate_stub = stub_request(:post, "#{server_url}/api/boxes/user/box/uploads/").
            to_return(status: 200, body: JSON.dump(initiate_response))

        upload_stub = stub_request(:put, upload_url).
            to_return(status: 404)

        expect { subject.upload_box }.
            to raise_error(VagrantPlugins::Registry::Errors::BoxUploadExpired)

        expect(initiate_stub).to have_been_requested.times(1)
        expect(upload_stub).to have_been_requested.times(1)
      end
    end

    context "when upload initialised with invalid data" do
      it "shows error message" do
        uploader =described_class.new(env,
                                      box_file.to_s,
                                      "#{server_url}/user/box",
                                      "0.1.asdf",
                                      "virtualbox")

        initiate_response = {
            "version" => ["Invlid version number."],
        }
        initiate_stub = stub_request(:post, "#{server_url}/api/boxes/user/box/uploads/").
            to_return(status: 400, body: JSON.dump(initiate_response))

        expect { uploader.upload_box }.
            to raise_error(VagrantPlugins::Registry::Errors::BoxUploadError)

        expect(initiate_stub).to have_been_requested.times(1)
      end
    end

    context "when server requests chunks out of order" do
      it "returns requested chunk" do
        uploader =described_class.new(env,
                                      box_file.to_s,
                                      "#{server_url}/user/box",
                                      "0.1.0",
                                      "virtualbox",
                                      chunk_size = 5)

        upload_url = "#{server_url}/api/boxes/user/box/uploads/123/"
        initiate_response = {
            "url" => upload_url,
        }
        initiate_stub = stub_request(:post, "#{server_url}/api/boxes/user/box/uploads/").
            to_return(status: 200, body: JSON.dump(initiate_response))

        upload_request_p1 = "box c"
        upload_headers_p1 = {
            "Accept" => "application/json",
            "Content-Type" => "application/octet-stream",
            "Content-Range" => "bytes 0-5/#{box_file.size}",
        }
        upload_response_p1 = {
            "offset" => 10,
        }

        upload_request_p3 = "t 123"
        upload_headers_p3 = {
            "Accept" => "application/json",
            "Content-Type" => "application/octet-stream",
            "Content-Range" => "bytes 10-#{box_file.size}/#{box_file.size}",
        }

        upload_stub = stub_request(:put, upload_url).
            with(body: upload_request_p1, headers: upload_headers_p1).
            to_return(status: 416, body: JSON.dump(upload_response_p1))
        upload_stub3 = stub_request(:put, upload_url).
            with(body: upload_request_p3, headers: upload_headers_p3).
            to_return(status: 416, body: JSON.dump(upload_response_p1)).then.
            to_return(status: 201)

        uploader.upload_box

        expect(initiate_stub).to have_been_requested.times(1)
        expect(upload_stub).to have_been_requested.times(1)
        expect(upload_stub3).to have_been_requested.times(2)
      end
    end

    context "when upload was interrupted" do
      it "it resumes upload" do
        upload_url = "#{server_url}/api/boxes/user/box/uploads/123/"
        subject.send(:store_upload_url, upload_url)

        # Need to reinitialise uploader, because interrupted URL checked in `new`
        uploader = described_class.new(env,
                                       box_file.to_s,
                                       "#{server_url}/user/box",
                                       "0.1.0",
                                       "virtualbox")

        upload_stub = stub_request(:put, upload_url).
            to_return(status: 201)

        uploader.upload_box

        expect(upload_stub).to have_been_requested.times(1)
      end
    end

  end

  describe "#upload_box!" do
    it "uploads box without resuming interrupted upload" do
      upload_url = "#{server_url}/api/boxes/user/box/uploads/123/"
      subject.send(:store_upload_url, upload_url)

      # Need to reinitialise uploader, because interrupted URL checked in `new`
      uploader = described_class.new(env,
                                     box_file.to_s,
                                     "#{server_url}/user/box",
                                     "0.1.0",
                                     "virtualbox")

      initiate_response = {
          "url" => upload_url,
      }
      initiate_stub = stub_request(:post, "#{server_url}/api/boxes/user/box/uploads/").
          to_return(status: 200, body: JSON.dump(initiate_response))

      upload_stub = stub_request(:put, upload_url).
          to_return(status: 201)

      uploader.upload_box!

      expect(initiate_stub).to have_been_requested.times(1)
      expect(upload_stub).to have_been_requested.times(1)
    end
  end

end
