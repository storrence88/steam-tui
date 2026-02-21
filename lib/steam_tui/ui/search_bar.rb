# frozen_string_literal: true

module SteamTui
  module Ui
    class SearchBar
      def initialize(pastel:)
        @pastel = pastel
      end

      # Returns a single-line string for the search bar.
      # When query is nil, renders a dim placeholder.
      def render(query:, width:)
        if query.nil?
          @pastel.dim("  Press / to search".ljust(width))
        else
          label  = @pastel.bold.cyan("/ ")
          cursor = @pastel.bold("|")
          text   = query.empty? ? cursor : "#{query}#{cursor}"
          "#{label}#{text}".ljust(width)
        end
      end
    end
  end
end
