module VagrantPlugins
  module Registry
    module Errors
      class Error < Vagrant::Errors::VagrantError
        error_namespace("vagrant_registry.errors")
      end

      class ServerError < Error
        error_key(:server_error)
      end

      class ServerUnreachable < Error
        error_key(:server_unreachable)
      end

      class NotLoggedIn < Error
        def error_message
          "You're not logged in"
        end
      end

      class BoxFileNotFound < Error
        def error_message
          "Box #{path} not found"
        end
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
        def error_message
          "Box upload terminated"
        end
      end

      class InvalidURL < Error
        def error_message
          "Invalid URL"
        end
      end

      class PermissionDenied < Error
        def error_message
          "You don't have permissions to perform this operation"
        end
      end

    end
  end
end
