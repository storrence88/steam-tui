# frozen_string_literal: true

module SteamTui
  module Ui
    class TreePane
      INDENT = "  "

      def initialize(genre_tree:, expanded_genres:, pastel:)
        @genre_tree      = genre_tree
        @expanded_genres = expanded_genres
        @pastel          = pastel
      end

      # Returns the flat ordered list of items the cursor can land on.
      # Each item is a Hash with :type (:genre or :game), plus relevant fields.
      # This is the single source of truth for cursor position resolution.
      def build_flat_list
        list = []
        @genre_tree.each do |genre, games|
          list << { type: :genre, genre: genre, games: games }
          if @expanded_genres.include?(genre)
            games.each do |game|
              list << { type: :game, game: game, parent_genre: genre }
            end
          end
        end
        list
      end

      # Returns Array<String> of rendered lines (exactly `height` lines).
      def render(height:, width:, cursor_pos:, search_mode:, filtered_games:)
        lines = if search_mode
                  render_search(filtered_games, cursor_pos, width)
                else
                  render_tree(cursor_pos, width)
                end

        # Pad or truncate to exact height
        lines = lines.first(height)
        lines += [""] * [height - lines.length, 0].max
        lines
      end

      private

      def render_tree(cursor_pos, width)
        flat  = build_flat_list
        lines = []

        flat.each.with_index do |item, idx|
          selected = idx == cursor_pos

          if item[:type] == :genre
            genre    = item[:genre]
            count    = item[:games].length
            expanded = @expanded_genres.include?(genre)
            arrow    = expanded ? "▼" : "▶"
            label    = "#{arrow} #{genre} (#{count})"
            lines << format_line(label, selected, width, bold: true)
          else
            game  = item[:game]
            label = "#{INDENT}├ #{game.name}"
            lines << format_line(label, selected, width)
          end
        end

        lines
      end

      def render_search(filtered_games, cursor_pos, width)
        return [@pastel.dim("  No results")] if filtered_games.nil? || filtered_games.empty?

        filtered_games.each.with_index.map do |game, idx|
          selected = idx == cursor_pos
          format_line("  #{game.name}", selected, width)
        end
      end

      def format_line(label, selected, width, bold: false)
        # Truncate label to fit width with indicator
        max_text = width - 3
        text = label.length > max_text ? "#{label[0, max_text - 1]}…" : label

        if selected
          indicator = @pastel.cyan(" ◀")
          line = text.ljust(width - 2) + indicator
          @pastel.on_bright_black(line)
        else
          text.ljust(width)
        end
      end
    end
  end
end
