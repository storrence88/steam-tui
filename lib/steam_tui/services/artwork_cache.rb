# frozen_string_literal: true

require "fileutils"
require "httparty"

module SteamTui
  module Services
    # Downloads and caches game artwork to ~/.cache/steam-tui/.
    # Returns the local path on success, nil when artwork is unavailable.
    # Enforces a simple LRU cap: if the cache exceeds MAX_ENTRIES files,
    # the oldest (by mtime) are evicted before writing a new one.
    class ArtworkCache
      CACHE_DIR   = File.expand_path("~/.cache/steam-tui")
      MAX_ENTRIES = 200

      def fetch(game)
        FileUtils.mkdir_p(CACHE_DIR)

        path = cache_path(game.appid)
        return path if File.exist?(path)

        # Try portrait capsule first, fall back to header image.
        [game.artwork_url, game.header_url].each do |url|
          downloaded = download(url, path)
          return path if downloaded
        end

        nil
      rescue StandardError
        nil
      end

      private

      def cache_path(appid)
        File.join(CACHE_DIR, "#{appid}.jpg")
      end

      def download(url, dest)
        resp = HTTParty.get(url, timeout: 10, follow_redirects: true)
        return false unless resp.success? && resp.body.bytesize > 0

        evict_if_full
        File.binwrite(dest, resp.body)
        true
      rescue StandardError
        false
      end

      def evict_if_full
        entries = Dir[File.join(CACHE_DIR, "*.jpg")].sort_by { |f| File.mtime(f) }
        return if entries.length < MAX_ENTRIES

        entries.first(entries.length - MAX_ENTRIES + 1).each { |f| File.delete(f) }
      end
    end
  end
end
