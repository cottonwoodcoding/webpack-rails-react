require 'net/http'
require 'uri'

module Repack
  # Webpack manifest loading, caching & entry point retrieval
  class Manifest
    # Raised if we can't read our webpack manifest for whatever reason
    class ManifestLoadError < StandardError
      def initialize(message, orig)
        super "#{message} (original error #{orig})"
      end
    end

    # Raised if a supplied entry point does not exist in the webpack manifest
    class EntryPointMissingError < StandardError
    end

    class << self
      # :nodoc:
      def asset_paths(source)
        paths = manifest["assetsByChunkName"][source]
        if paths
          # Can be either a string or an array of strings.
          # Do not include source maps as they are not javascript
          [paths].flatten.reject { |p| p =~ /.*\.map$/ }.map do |p|
            "/#{::Rails.configuration.repack.public_path}/#{p}"
          end
        else
          raise EntryPointMissingError, "Can't find entry point '#{source}' in webpack manifest"
        end
      end

      private

      def manifest
        if ::Rails.configuration.repack.dev_server.enabled
          # Don't cache if we're in dev server mode, manifest may change ...
          load_manifest
        else
          # ... otherwise cache at class level, as JSON loading/parsing can be expensive
          @manifest ||= load_manifest
        end
      end

      def load_manifest
        data = if ::Rails.configuration.repack.dev_server.enabled
          load_dev_server_manifest
        else
          load_static_manifest
        end
        JSON.parse(data)
      end

      def load_dev_server_manifest
        http = Net::HTTP.new(
          "localhost",
          ::Rails.configuration.repack.dev_server.port)
        http.use_ssl = ::Rails.configuration.repack.dev_server.https
        http.verify_mode = OpenSSL::SSL::VERIFY_NONE
        http.get(dev_server_path).body
      rescue => e
        raise ManifestLoadError.new("Could not load manifest from webpack-dev-server at #{dev_server_url} - is it running, and is stats-webpack-plugin loaded?", e)
      end

      def load_static_manifest
        File.read(static_manifest_path)
      rescue => e
        raise ManifestLoadError.new("Could not load compiled manifest from #{static_manifest_path} - have you run `rake webpack:compile`?", e)
      end

      def static_manifest_path
        ::Rails.root.join(
          ::Rails.configuration.repack.output_dir,
          ::Rails.configuration.repack.manifest_filename
        )
      end

      def dev_server_path
        "/#{::Rails.configuration.repack.public_path}/#{::Rails.configuration.repack.manifest_filename}"
      end

      def dev_server_url
        "http://localhost:#{::Rails.configuration.repack.dev_server.port}#{dev_server_path}"
      end
    end
  end
end