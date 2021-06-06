# frozen_string_literal: true

require "English"

require_relative "choices"
require_relative "paginator"
require_relative "block_paginator"

module TTY
  class Prompt
    # A class responsible for rendering select list menu
    # Used by {Prompt} to display interactive menu.
    #
    # @api private
    class List
      # Allowed keys for filter, along with backspace and canc.
      FILTER_KEYS_MATCHER = /\A([[:alnum:]]|[[:punct:]]|[[:blank:]])\Z/.freeze

      # Checks type of default parameter to be integer
      INTEGER_MATCHER = /\A\d+\Z/.freeze

      # Create instance of TTY::Prompt::List menu.
      #
      # @param Hash options
      #   the configuration options
      # @option options [Symbol] :default
      #   the default active choice, defaults to 1
      # @option options [Symbol] :color
      #   the color for the selected item, defualts to :green
      # @option options [Symbol] :marker
      #   the marker for the selected item
      # @option options [String] :enum
      #   the delimiter for the item index
      #
      # @api public
      def initialize(prompt, **options)
        check_options_consistency(options)

        @prompt       = prompt
        @prefix       = options.fetch(:prefix) { @prompt.prefix }
        @enum         = options.fetch(:enum) { nil }
        @default      = Array(options[:default])
        @choices      = Choices.new
        @active_color = options.fetch(:active_color) { @prompt.active_color }
        @help_color   = options.fetch(:help_color) { @prompt.help_color }
        @cycle        = options.fetch(:cycle) { false }
        @filterable   = options.fetch(:filter) { false }
        @symbols      = @prompt.symbols.merge(options.fetch(:symbols, {}))
        @quiet        = options.fetch(:quiet) { @prompt.quiet }
        @confirm_keys  = init_action_keys(options.fetch(:confirm_keys) { default_confirm_keys })
        @filter       = []
        @filter_cache = {}
        @help         = options[:help]
        @show_help    = options.fetch(:show_help) { :start }
        @first_render = true
        @done         = false
        @per_page     = options[:per_page]
        @paginator    = Paginator.new
        @block_paginator = BlockPaginator.new
        @by_page      = false
        @paging_changed = false
      end

      # Change symbols used by this prompt
      #
      # @param [Hash] new_symbols
      #   the new symbols to use
      #
      # @api public
      def symbols(new_symbols = (not_set = true))
        return @symbols if not_set

        @symbols.merge!(new_symbols)
      end

      # Set default option selected
      #
      # @api public
      def default(*default_values)
        @default = default_values
      end

      # Default confirm keys, if not explicitly configured
      #
      # @api private
      def default_confirm_keys
        %i[space return enter].freeze
      end

      # Initialize any default or custom action keys
      # setting up their labels and dealing with compat
      #
      # @param [Array<Symbol, String, Hash{Symbol, String => String}>]
      #
      # @return [Hash{Symbol, String => String}]
      #
      # @api private
      def init_action_keys(keys)
        keys = keys_with_labels(keys)
        ensure_eol_compat(keys)
      end

      # Normalize a list of key symbols or symbol-label hashes
      # into a single symbol-label lookup hash.
      #
      # @example Only with symbol keys
      #   keys = [:enter, :ctrl_s]
      #   keys_with_labels(keys)
      #   # => {enter: "Enter", ctrl_s: "Ctrl+S"}
      #
      # @example With mixed keys
      #   keys = [:enter, {ctrl_s: "Ctrl-S"}]
      #   keys_with_labels(keys)
      #   # => {enter: "Enter", ctrl_s: "Ctrl-S"}
      #
      # @param [Array<Symbol, String, Hash{Symbol, String => String}>]
      #
      # @return [String]
      #
      # @api private
      def keys_with_labels(keys)
        keys.reduce({}) do |result, key|
          obj = key.is_a?(::Hash) ? key : {key => key_help_label(key)}
          result.merge(obj)
        end
      end

      # Convert a key name into a human-readable label
      #
      # @param [Symbol, String]
      #
      # @return [String]
      #
      # @api private
      def key_help_label(key_name)
        if key_name == :return
          "Enter"
        else
          key_name.to_s.split("_").map(&:capitalize).join("+")
        end
      end

      # Ensure that if any EOL char is passed as an action key
      # then all EOL chars are included (for cross-system compat)
      # Maintain any custom labels.
      #
      # @example
      #   keys = {return: "Enter", ctrl_s: "Ctrl+S"}
      #   ensure_eol_compat(keys)
      #   # => {enter: "Enter", return: "Enter", ctrl_s: "Ctrl+S"}
      #
      # @param [Hash{Symbol, String => String}]
      #
      # @return [Hash{Symbol, String => String}]
      #
      # @api private
      def ensure_eol_compat(keys)
        eol_symbols = %i[enter return]
        key_symbols = keys.keys.sort_by(&:to_s)
        key_intersection = eol_symbols & key_symbols

        case key_intersection
        when [], eol_symbols
          keys
        else
          eol_label = keys[key_intersection.first]
          missing_key = (eol_symbols - key_intersection).first
          keys.merge({missing_key => eol_label})
        end
      end

      # Select paginator based on the current navigation key
      #
      # @return [Paginator]
      #
      # @api private
      def paginator
        @by_page ? @block_paginator : @paginator
      end

      # Synchronize paginators start positions
      #
      # @api private
      def sync_paginators
        if @by_page
          if @paginator.start_index
            @block_paginator.reset!
            @block_paginator.start_index = @paginator.start_index
          end
        else
          if @block_paginator.start_index
            @paginator.reset!
            @paginator.start_index = @block_paginator.start_index
          end
        end
      end

      # Set number of items per page
      #
      # @api public
      def per_page(value)
        @per_page = value
      end

      def page_size
        (@per_page || Paginator::DEFAULT_PAGE_SIZE)
      end

      # Check if list is paginated
      #
      # @return [Boolean]
      #
      # @api private
      def paginated?
        choices.size > page_size
      end

      # Provide help information
      #
      # @param [String] value
      #   the new help text
      #
      # @return [String]
      #
      # @api public
      def help(value = (not_set = true))
        return @help if !@help.nil? && not_set

        @help = (@help.nil? && !not_set) ? value : default_help
      end

      # Change when help is displayed
      #
      # @api public
      def show_help(value = (not_set = true))
        return @show_help if not_set

        @show_help = value
      end

      # Information about arrow keys
      #
      # @return [String]
      #
      # @api private
      def arrows_help
        up_down = @symbols[:arrow_up] + "/" + @symbols[:arrow_down]
        left_right = @symbols[:arrow_left] + "/" + @symbols[:arrow_right]

        arrows = [up_down]
        arrows << "/" if paginated?
        arrows << left_right if paginated?
        arrows.join
      end

      # Information about keys that confirm the selection
      #
      # @example Get help string for many keys
      #   keys = {return: "Enter", ctrl_s: "Ctrl+S", space: "Space"}
      #   keys_help(keys)
      #   # => "Enter, Ctrl+S or Space"
      #
      # @example Get help string for one key
      #   keys = {return: "Enter"}
      #   keys_help(keys)
      #   # => "Enter"
      #
      # @param [Hash{Symbol, String => String}]
      #
      # @return [String]
      #
      # @api private
      def keys_help(keys)
        labels = keys.values.uniq
        if labels.length == 1
          labels[0]
        else
          "#{labels[0..-2].join(', ')} or #{labels[-1]}"
        end
      end

      # Default help text
      #
      # Note that enumeration and filter are mutually exclusive
      #
      # @api public
      def default_help
        str = []
        str << "(Press "
        str << "#{arrows_help} arrow"
        str << " or 1-#{choices.size} number" if enumerate?
        str << " to move"
        str << (filterable? ? "," : " and")
        str << " #{keys_help(@confirm_keys)} to select"
        str << " and letters to filter" if filterable?
        str << ")"
        str.join
      end

      # Set selecting active index using number pad
      #
      # @api public
      def enum(value)
        @enum = value
      end

      # Set whether selected answers are echoed
      #
      # @api public
      def quiet(value)
        @quiet = value
      end

      # Add a single choice
      #
      # @api public
      def choice(*value, &block)
        @filter_cache = {}
        if block
          @choices << (value << block)
        else
          @choices << value
        end
      end

      # Add multiple choices, or return them.
      #
      # @param [Array[Object]] values
      #   the values to add as choices; if not passed, the current
      #   choices are displayed.
      #
      # @api public
      def choices(values = (not_set = true))
        if not_set
          if !filterable? || @filter.empty?
            @choices
          else
            filter_value = @filter.join.downcase
            @filter_cache[filter_value] ||= @choices.enabled.select do |choice|
              choice.name.to_s.downcase.include?(filter_value)
            end
          end
        else
          @filter_cache = {}
          values.each { |val| @choices << val }
        end
      end

      # Call the list menu by passing question and choices
      #
      # @param [String] question
      #
      # @param
      # @api public
      def call(question, possibilities, &block)
        choices(possibilities)
        @question = question
        block.call(self) if block
        setup_defaults
        @prompt.subscribe(self) do
          render
        end
      end

      # Check if list is enumerated
      #
      # @return [Boolean]
      def enumerate?
        !@enum.nil?
      end

      def keynum(event)
        return unless enumerate?

        value = event.value.to_i
        return unless (1..choices.count).cover?(value)
        return if choices[value - 1].disabled?

        @active = value
      end

      def search_choice_in(searchable)
        searchable.find { |i| !choices[i - 1].disabled? }
      end

      def keyup(*)
        searchable  = (@active - 1).downto(1).to_a
        prev_active = search_choice_in(searchable)

        if prev_active
          @active = prev_active
        elsif @cycle
          searchable  = choices.length.downto(1).to_a
          prev_active = search_choice_in(searchable)

          @active = prev_active if prev_active
        end

        @paging_changed = @by_page
        @by_page = false
      end

      def keydown(*)
        searchable  = ((@active + 1)..choices.length)
        next_active = search_choice_in(searchable)

        if next_active
          @active = next_active
        elsif @cycle
          searchable = (1..choices.length)
          next_active = search_choice_in(searchable)

          @active = next_active if next_active
        end
        @paging_changed = @by_page
        @by_page = false
      end

      # Moves all choices page by page keeping the current selected item
      # at the same level on each page.
      #
      # When the choice on a page is outside of next page range then
      # adjust it to the last item, otherwise leave unchanged.
      def keyright(*)
        choices_size = choices.size
        if (@active + page_size) <= choices_size
          searchable = ((@active + page_size)..choices_size)
          @active = search_choice_in(searchable)
        elsif @active <= choices_size # last page shorter
          current   = @active % page_size
          remaining = choices_size % page_size

          if current.zero? || (remaining > 0 && current > remaining)
            searchable = choices_size.downto(0).to_a
            @active = search_choice_in(searchable)
          elsif @cycle
            searchable = ((current.zero? ? page_size : current)..choices_size)
            @active = search_choice_in(searchable)
          end
        end

        @paging_changed = !@by_page
        @by_page = true
      end
      alias keypage_down keyright

      def keyleft(*)
        if (@active - page_size) > 0
          searchable = ((@active - page_size)..choices.size)
          @active = search_choice_in(searchable)
        elsif @cycle
          searchable = choices.size.downto(1).to_a
          @active = search_choice_in(searchable)
        end
        @paging_changed = !@by_page
        @by_page = true
      end
      alias keypage_up keyleft

      # Callback fired when a confirm key is pressed
      #
      # @api private
      def confirm
        @done = true unless choices.empty?
      end

      def keypress(event)
        if !(@confirm_keys.keys & [event.key.name, event.value]).empty?
          confirm
        elsif event.key.name == :tab
          keydown
        elsif filterable? && event.value =~ FILTER_KEYS_MATCHER
          @filter << event.value
          @active = 1
        end
      end

      def keydelete(*)
        return unless filterable?

        @filter.clear
        @active = 1
      end

      def keybackspace(*)
        return unless filterable?

        @filter.pop
        @active = 1
      end

      private

      def check_options_consistency(options)
        if options.key?(:enum) && options.key?(:filter)
          raise ConfigurationError,
                "Enumeration can't be used with filter"
        end
      end

      # Setup default option and active selection
      #
      # @return [Integer]
      #
      # @api private
      def setup_defaults
        validate_defaults

        if @default.empty?
          # no default, pick the first non-disabled choice
          @active = choices.index { |choice| !choice.disabled? } + 1
        elsif @default.first.to_s =~ INTEGER_MATCHER
          @active = @default.first
        elsif default_choice = choices.find_by(:name, @default.first)
          @active = choices.index(default_choice) + 1
        end
      end

      # Validate default indexes to be within range
      #
      # @raise [ConfigurationError]
      #   raised when the default index is either non-integer,
      #   out of range or clashes with disabled choice item.
      #
      # @api private
      def validate_defaults
        @default.each do |d|
          msg = if d.nil? || d.to_s.empty?
                  "default index must be an integer in range (1 - #{choices.size})"
                elsif d.to_s !~ INTEGER_MATCHER
                  validate_default_name(d)
                elsif d < 1 || d > choices.size
                  "default index `#{d}` out of range (1 - #{choices.size})"
                elsif (dflt_choice = choices[d - 1]) && dflt_choice.disabled?
                  "default index `#{d}` matches disabled choice"
                end

          raise(ConfigurationError, msg) if msg
        end
      end

      # Validate default choice name
      #
      # @param [String] name
      #   the name to verify
      #
      # @return [String]
      #
      # @api private
      def validate_default_name(name)
        default_choice = choices.find_by(:name, name.to_s)
        if default_choice.nil?
          "no choice found for the default name: #{name.inspect}"
        elsif default_choice.disabled?
          "default name #{name.inspect} matches disabled choice"
        end
      end

      # Render a selection list.
      #
      # By default the result is printed out.
      #
      # @return [Object] value
      #   return the selected value
      #
      # @api private
      def render
        @prompt.print(@prompt.hide)
        until @done
          question = render_question
          @prompt.print(question)
          @prompt.read_keypress

          # Split manually; if the second line is blank (when there are no
          # matching lines), it won't be included by using String#lines.
          question_lines = question.split($INPUT_RECORD_SEPARATOR, -1)

          @prompt.print(refresh(question_lines_count(question_lines)))
        end
        @prompt.print(render_question) unless @quiet
        answer
      ensure
        @prompt.print(@prompt.show)
      end

      # Count how many screen lines the question spans
      #
      # @return [Integer]
      #
      # @api private
      def question_lines_count(question_lines)
        question_lines.reduce(0) do |acc, line|
          acc + @prompt.count_screen_lines(line)
        end
      end

      # Find value for the choice selected
      #
      # @return [nil, Object]
      #
      # @api private
      def answer
        choices[@active - 1].value
      end

      # Clear screen lines
      #
      # @param [String]
      #
      # @api private
      def refresh(lines)
        @prompt.clear_lines(lines)
      end

      # Render question with instructions and menu
      #
      # @return [String]
      #
      # @api private
      def render_question
        header = ["#{@prefix}#{@question} #{render_header}\n"]
        @first_render = false
        unless @done
          header << render_menu
        end
        header.join
      end

      # Is filtering enabled?
      #
      # @return [Boolean]
      #
      # @api private
      def filterable?
        @filterable
      end

      # Header part showing the current filter
      #
      # @return String
      #
      # @api private
      def filter_help
        "(Filter: #{@filter.join.inspect})"
      end

      # Check if help is shown only on start
      #
      # @api private
      def help_start?
        @show_help =~ /start/i
      end

      # Check if help is always displayed
      #
      # @api private
      def help_always?
        @show_help =~ /always/i
      end

      # Render initial help and selected choice
      #
      # @return [String]
      #
      # @api private
      def render_header
        if @done
          selected_item = choices[@active - 1].name
          @prompt.decorate(selected_item.to_s, @active_color)
        elsif (@first_render && (help_start? || help_always?)) ||
              (help_always? && !@filter.any?)
          @prompt.decorate(help, @help_color)
        elsif filterable? && @filter.any?
          @prompt.decorate(filter_help, @help_color)
        end
      end

      # Render menu with choices to select from
      #
      # @return [String]
      #
      # @api private
      def render_menu
        output = []

        sync_paginators if @paging_changed
        paginator.paginate(choices, @active, @per_page) do |choice, index|
          num = enumerate? ? (index + 1).to_s + @enum + " " : ""
          message = if index + 1 == @active && !choice.disabled?
                      selected = "#{@symbols[:marker]} #{num}#{choice.name}"
                      @prompt.decorate(selected.to_s, @active_color)
                    elsif choice.disabled?
                      @prompt.decorate(@symbols[:cross], :red) +
                        " #{num}#{choice.name} #{choice.disabled}"
                    else
                      "  #{num}#{choice.name}"
                    end
          end_index = paginated? ? paginator.end_index : choices.size - 1
          newline = (index == end_index) ? "" : "\n"
          output << (message + newline)
        end

        output.join
      end
    end # List
  end # Prompt
end # TTY
