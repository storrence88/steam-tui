# frozen_string_literal: true

module SteamTui
  module Ui
    class SearchBar
      def initialize(pastel:)
        @pastel = pastel
      end

      # Returns a single-line string for the search bar.
      # When query is nil, renders a dim placeholder.
      def render(query:, width:, result_count: nil)
        if query.nil?
          @pastel.dim("  Press / to search".ljust(width))
        else
          label  = @pastel.bold.cyan("/ ")
          cursor = @pastel.bold("|")
          text   = query.empty? ? cursor : "#{query}#{cursor}"

          if !query.empty? && !result_count.nil?
            count_tag = @pastel.dim(" (#{result_count} result#{"s" if result_count != 1})")
            "#{label}#{text}#{count_tag}".ljust(width)
          else
            "#{label}#{text}".ljust(width)
          end
        end
      end
    end
  end
end
