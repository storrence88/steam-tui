# frozen_string_literal: true

module SteamTui
  module Models
    Game = Data.define(:appid, :name, :genres, :playtime_forever) do
      # playtime_forever is in minutes; convert to hours for display
      def playtime_hours
        (playtime_forever / 60.0).round(1)
      end

      def primary_genre
        genres.first || "Uncategorized"
      end
    end
  end
end
