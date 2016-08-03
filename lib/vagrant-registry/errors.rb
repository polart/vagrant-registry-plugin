module VagrantPlugins
  module Registry
    module Errors
      class Error < Vagrant::Errors::VagrantError
        error_namespace("registry.errors")
      end

      class ServerError < Error
        error_key(:server_error)
      end

      class ServerUnreachable < Error
        error_key(:server_unreachable)
      end

      class NotLoggedIn < Error
        error_key(:not_logged_in)
      end

      class BoxFileNotFound < Error
        error_key(:box_file_missing)
      end

      class BoxUploadError < Error
        error_key(:box_upload_error)
      end

      class BoxCreateError < Error
        error_key(:box_create_error)
      end

      class BoxUploadExpired < Error
        error_key(:box_upload_expired)
      end

      class BoxUploadTerminatedByUser < Error
        error_key(:box_upload_terminated)
      end

      class InvalidURL < Error
        error_key(:invalid_url)
      end

      class PermissionDenied < Error
        error_key(:permission_denied)
      end

    end
  end
end
