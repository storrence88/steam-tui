# frozen_string_literal: true

module SteamTui
  module Services
    # Renders a local image file as an array of terminal-printable strings
    # (one string per line) using the best available renderer.
    #
    # Priority:
    #   1. chafa  — system CLI; auto-detects Kitty / iTerm2 / Sixel / ANSI
    #   2. imgcat — optional Ruby gem; iTerm2 / WezTerm / VSCode inline images
    #   3. nil    — no renderer available; caller shows a placeholder instead
    class ImageRenderer
      # Detect once at class load time so we don't shell out on every render.
      CHAFA_AVAILABLE  = system("which chafa > /dev/null 2>&1")
      IMGCAT_AVAILABLE = begin
        require "imgcat"
        true
      rescue LoadError
        false
      end

      def self.available?
        CHAFA_AVAILABLE || IMGCAT_AVAILABLE
      end

      # Returns Array<String> of lines, or nil when no renderer is available.
      # `width` and `height` are in terminal character cells.
      def render(path, width:, height:)
        return nil unless File.exist?(path.to_s)

        if CHAFA_AVAILABLE
          render_chafa(path, width, height)
        elsif IMGCAT_AVAILABLE
          render_imgcat(path)
        end
      rescue StandardError
        nil
      end

      private

      def render_chafa(path, width, height)
        # --format auto lets chafa pick the best protocol for the terminal.
        # --size caps the output dimensions so it fits inside the pane.
        raw = `chafa --format auto --size #{width}x#{height} "#{path}" 2>/dev/null`
        return nil if raw.empty?

        raw.split("\n")
      end

      def render_imgcat(path)
        # imgcat embeds the image as a single OSC escape sequence; wrap it
        # in an array so it fits the Array<String> contract.
        data = File.binread(path)
        [Imgcat.encode(data)]
      end
    end
  end
end
