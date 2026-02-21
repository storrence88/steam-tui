# frozen_string_literal: true

require "set"

module SteamTui
  module Models
    FamilyMember = Data.define(:steamid, :persona_name, :game_ids) do
      # O(1) ownership check — called on every render for each family member
      def owns?(appid)
        game_ids.include?(appid)
      end
    end
  end
end
