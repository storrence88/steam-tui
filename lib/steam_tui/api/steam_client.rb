# frozen_string_literal: true

require "httparty"
require "steam_tui/models/game"
require "steam_tui/models/family_member"

module SteamTui
  module Api
    class SteamClient
      STEAM_API_BASE  = "https://api.steampowered.com"
      FAMILY_API_BASE = "https://api.steampowered.com"

      def initialize(api_key:, steam_id:)
        @api_key  = api_key
        @steam_id = steam_id
      end

      # Returns Array<Models::Game> for the primary user.
      def fetch_owned_games(steam_id = @steam_id)
        resp = HTTParty.get(
          "#{STEAM_API_BASE}/IPlayerService/GetOwnedGames/v1/",
          query: {
            key: @api_key,
            steamid: steam_id,
            include_appinfo: 1,
            include_played_free_games: 1,
            format: "json"
          },
          timeout: 15
        )
        games_json = resp.dig("response", "games") || []
        games_json.map do |g|
          Models::Game.new(
            appid:            g["appid"],
            name:             g["name"] || "Unknown",
            genres:           [],           # enriched in v2 via store API
            playtime_forever: g["playtime_forever"] || 0
          )
        end
      end

      # Returns Array<String> of SteamIDs for family group members (excluding self).
      # Falls back to FAMILY_STEAM_IDS env var on 403 or empty response.
      def fetch_family_member_ids
        resp = HTTParty.get(
          "#{FAMILY_API_BASE}/IFamilyGroupsService/GetFamilyGroupForUser/v1/",
          query: { key: @api_key, steamid: @steam_id, format: "json" },
          timeout: 15
        )

        if resp.code == 403 || resp.code == 401
          return fallback_family_ids
        end

        members = resp.dig("response", "family_group", "members") || []
        ids = members.map { |m| m["steamid"].to_s }.reject { |id| id == @steam_id.to_s }
        ids.empty? ? fallback_family_ids : ids
      rescue StandardError
        fallback_family_ids
      end

      # Returns Hash<steamid_string => persona_name> for an array of SteamIDs.
      def fetch_player_summaries(steam_ids)
        return {} if steam_ids.empty?

        # API accepts up to 100 IDs per request
        steam_ids.each_slice(100).each_with_object({}) do |batch, result|
          resp = HTTParty.get(
            "#{STEAM_API_BASE}/ISteamUser/GetPlayerSummaries/v2/",
            query: { key: @api_key, steamids: batch.join(","), format: "json" },
            timeout: 15
          )
          players = resp.dig("response", "players") || []
          players.each { |p| result[p["steamid"].to_s] = p["personaname"] }
        end
      end

      # Returns a Models::FamilyMember for a given steamid + persona_name.
      def build_family_member(steamid:, persona_name:)
        games = fetch_owned_games(steamid)
        Models::FamilyMember.new(
          steamid:      steamid.to_s,
          persona_name: persona_name,
          game_ids:     Set.new(games.map(&:appid))
        )
      rescue StandardError
        # Library may be private — return member with empty game set
        Models::FamilyMember.new(
          steamid:      steamid.to_s,
          persona_name: persona_name,
          game_ids:     Set.new
        )
      end

      private

      def fallback_family_ids
        raw = ENV.fetch("FAMILY_STEAM_IDS", "")
        raw.split(",").map(&:strip).reject(&:empty?)
      end
    end
  end
end
