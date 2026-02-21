# frozen_string_literal: true

module SteamTui
  module Ui
    class DetailPane
      def initialize(family_members:, pastel:)
        @family_members = family_members
        @pastel         = pastel
      end

      # Returns Array<String> of rendered lines (exactly `height` lines).
      def render(height:, width:, game:)
        lines = game ? render_game(game, width) : render_empty(width)

        lines = lines.first(height)
        lines += [""] * [height - lines.length, 0].max
        lines
      end

      private

      def render_game(game, width)
        owners = @family_members.select { |m| m.owns?(game.appid) }
        total  = @family_members.length

        lines = []
        lines << @pastel.bold(truncate("  #{game.name}", width))
        lines << ""
        lines << "  AppID:    #{game.appid}"
        lines << "  Playtime: #{game.playtime_display}"
        lines << ""
        lines << @pastel.dim("  Family ownership:")

        @family_members.each do |member|
          owned  = member.owns?(game.appid)
          mark   = owned ? @pastel.green("✓") : @pastel.red("✗")
          status = owned ? @pastel.green("owned") : @pastel.dim("not owned")
          name   = truncate(member.persona_name, 20).ljust(20)
          lines << "    #{mark} #{name}  — #{status}"
        end

        lines << ""
        lines << @pastel.dim("  Copies in family: #{owners.length} / #{total} members")
        lines
      end

      def render_empty(width)
        [
          "",
          @pastel.dim("  Select a game to see details."),
          ""
        ]
      end

      def truncate(str, max)
        str.length > max ? "#{str[0, max - 1]}…" : str
      end
    end
  end
end
