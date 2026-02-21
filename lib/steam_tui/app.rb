# frozen_string_literal: true

require "set"
require "tty-reader"
require "tty-screen"
require "tty-cursor"
require "pastel"

require "steam_tui/api/steam_client"
require "steam_tui/models/game"
require "steam_tui/models/family_member"
require "steam_tui/ui/search_bar"
require "steam_tui/ui/tree_pane"
require "steam_tui/ui/detail_pane"

module SteamTui
  class App
    def initialize
      @pastel  = Pastel.new
      @cursor  = TTY::Cursor
      @reader  = TTY::Reader.new(interrupt: :exit)

      # Data state
      @games          = []          # Array<Models::Game>  — your library
      @genre_tree     = {}          # Hash<genre_string => Array<Game>>
      @family_members = []          # Array<Models::FamilyMember> (all members incl. self)

      # UI state
      @cursor_pos      = 0          # index into flat_list
      @expanded_genres = Set.new    # which genre names are expanded
      @search_query    = nil        # nil = not searching; "" = active, empty
      @filtered_games  = nil        # nil = not searching; Array<Game> = results
      @selected_game   = nil        # Models::Game currently shown in detail pane

      # Sub-panes (instantiated after data loads so they receive state refs)
      @tree_pane   = nil
      @detail_pane = nil
      @search_bar  = nil
    end

    def run
      load_data
      init_ui
      run_loop
    end

    # ── Data loading ──────────────────────────────────────────────────────────

    def load_data
      print_loading("Connecting to Steam API…")

      api_key  = ENV.fetch("STEAM_API_KEY") { abort "Missing STEAM_API_KEY in .env" }
      steam_id = ENV.fetch("STEAM_ID")      { abort "Missing STEAM_ID in .env" }

      client = Api::SteamClient.new(api_key: api_key, steam_id: steam_id)

      print_loading("Fetching your game library…")
      @games = client.fetch_owned_games

      print_loading("Fetching family group…")
      member_ids = client.fetch_family_member_ids

      all_ids = ([steam_id] + member_ids).uniq

      print_loading("Fetching player names…")
      names = client.fetch_player_summaries(all_ids)

      @family_members = all_ids.map.with_index do |sid, idx|
        persona = names[sid.to_s] || "Member #{idx + 1}"
        print_loading("Fetching library for #{persona}…")
        client.build_family_member(steamid: sid, persona_name: persona)
      end

      @genre_tree = build_genre_tree(@games)
    end

    def build_genre_tree(games)
      tree = games.group_by(&:primary_genre)
      tree.transform_values! { |g| g.sort_by { |game| game.name.downcase } }
      tree.sort_by { |genre, _| genre.downcase }.to_h
    end

    # ── UI init ───────────────────────────────────────────────────────────────

    def init_ui
      @search_bar  = Ui::SearchBar.new(pastel: @pastel)
      @tree_pane   = Ui::TreePane.new(
        genre_tree:      @genre_tree,
        expanded_genres: @expanded_genres,
        pastel:          @pastel
      )
      @detail_pane = Ui::DetailPane.new(
        family_members: @family_members,
        pastel:         @pastel
      )
    end

    # ── Event loop ────────────────────────────────────────────────────────────

    def run_loop
      system("clear")
      render

      @reader.on(:keypress) { |event| handle_keypress(event) }
      @reader.read_keypress(nonblock: false) until @quit
    rescue Interrupt
      # Ctrl+C — clean exit
    ensure
      print @cursor.show
      system("clear")
    end

    def handle_keypress(event)
      key_name = event.key.name
      char     = event.value

      if @search_query
        handle_search_input(key_name, char)
      else
        handle_nav_input(key_name, char)
      end

      render
    end

    def handle_nav_input(key_name, char)
      flat = @tree_pane.build_flat_list

      # Special keys (arrows, Enter) — key_name is a Symbol
      case key_name
      when :up    then move_cursor(-1, flat)
      when :down  then move_cursor(1, flat)
      when :right, :return
        expand_or_select(flat)
      when :left
        collapse(flat)
      end

      # Character keys — event.key.name is :alpha for ALL lowercase letters;
      # the actual character is only available in event.value (char).
      case char
      when "k" then move_cursor(-1, flat)
      when "j" then move_cursor(1, flat)
      when "l" then expand_or_select(flat)
      when "h" then collapse(flat)
      when "/" then enter_search_mode
      when "q" then @quit = true
      end
    end

    def handle_search_input(key_name, char)
      case key_name
      when :escape
        exit_search_mode
      when :backspace, :delete
        @search_query = @search_query[0..-2]
        update_search_results
      when :return
        # select highlighted filtered game
        if @filtered_games&.any?
          @selected_game = @filtered_games[@cursor_pos]
          exit_search_mode
        end
      when :up
        move_cursor(-1, @filtered_games || [])
      when :down
        move_cursor(1, @filtered_games || [])
      else
        if char&.match?(/\A[[:print:]]\z/)
          @search_query += char
          update_search_results
        end
      end
    end

    def expand_or_select(flat)
      item = flat[@cursor_pos]
      if item&.dig(:type) == :genre
        @expanded_genres.add(item[:genre])
      elsif item&.dig(:type) == :game
        @selected_game = item[:game]
      end
    end

    def collapse(flat)
      item  = flat[@cursor_pos]
      genre = item&.dig(:genre) || item&.dig(:parent_genre)
      @expanded_genres.delete(genre) if genre
    end

    def move_cursor(delta, list)
      max = [list.length - 1, 0].max
      @cursor_pos = (@cursor_pos + delta).clamp(0, max)
    end

    def enter_search_mode
      @search_query   = ""
      @filtered_games = []
      @cursor_pos     = 0
    end

    def exit_search_mode
      @search_query   = nil
      @filtered_games = nil
      @cursor_pos     = 0
    end

    def update_search_results
      if @search_query.empty?
        @filtered_games = []
        @cursor_pos     = 0
        return
      end

      q = @search_query.downcase

      # Pass 1 — substring: query appears literally anywhere in the name
      substring = @games.select { |g| g.name.downcase.include?(q) }

      # Pass 2 — subsequence: every character appears in order (fzf-style)
      # e.g. "hlf" matches "Half-Life" but not "Lethal Company"
      subsequence = @games.select do |g|
        next false if substring.include?(g)
        name = g.name.downcase
        pos  = 0
        q.each_char.all? do |c|
          i = name.index(c, pos)
          break false unless i
          pos = i + 1
        end
      end

      @filtered_games = substring + subsequence
      @cursor_pos = 0
    end

    # ── Render ────────────────────────────────────────────────────────────────

    def render
      return if @quit

      width  = TTY::Screen.width
      height = TTY::Screen.height

      output = String.new
      output << "\e[H"   # move cursor to top-left (home)

      # Search bar (1 line)
      output << @search_bar.render(query: @search_query, width: width)
      output << "\n"

      # Panes take remaining height minus header + status line
      pane_height = height - 3
      left_width  = (width * 0.35).to_i
      right_width = width - left_width - 1  # -1 for divider

      left_lines = @tree_pane.render(
        height:          pane_height,
        width:           left_width,
        cursor_pos:      @cursor_pos,
        search_mode:     !@search_query.nil?,
        filtered_games:  @filtered_games
      )

      right_lines = @detail_pane.render(
        height: pane_height,
        width:  right_width,
        game:   @selected_game
      )

      pane_height.times do |i|
        left  = (left_lines[i]  || "").ljust(left_width)
        right = (right_lines[i] || "").ljust(right_width)
        output << "#{left}│#{right}\n"
      end

      # Status bar
      output << @pastel.dim("[jk] move  [l] open  [h] close  [/] search  [q] quit".ljust(width))

      print output
    end

    private

    def print_loading(msg)
      print "\r\e[K#{msg}"
    end
  end
end
