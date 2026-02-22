# frozen_string_literal: true

module SteamTui
  module Models
    Game = Data.define(:appid, :name, :genres, :playtime_forever) do
      # playtime_forever is in minutes; format as "Xh Ym", "Ym", or "Never played"
      def playtime_display
        return "Never played" if playtime_forever == 0
        hours   = playtime_forever / 60
        minutes = playtime_forever % 60
        if hours > 0
          minutes > 0 ? "#{hours}h #{minutes}m" : "#{hours}h"
        else
          "#{minutes}m"
        end
      end

      def primary_genre
        genres.first || "Uncategorized"
      end

      # Public CDN URLs — no authentication required.
      # Portrait capsule (600×900) is preferred; header (460×215) is the fallback.
      def artwork_url
        "https://cdn.cloudflare.steamstatic.com/steam/apps/#{appid}/library_600x900.jpg"
      end

      def header_url
        "https://cdn.cloudflare.steamstatic.com/steam/apps/#{appid}/header.jpg"
      end
    end
  end
end
