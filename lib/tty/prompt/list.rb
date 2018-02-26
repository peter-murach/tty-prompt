# encoding: utf-8

require "English"

require_relative 'choices'
require_relative 'paginator'
require_relative 'symbols'

module TTY
  class Prompt
    # A class responsible for rendering select list menu
    # Used by {Prompt} to display interactive menu.
    #
    # @api private
    class List
      include Symbols

      HELP = '(Use arrow%s keys, press Enter to select%s)'

      PAGE_HELP = '(Move up or down to reveal more choices)'

      # Allowed keys for filter, along with backspace and canc.
      FILTER_KEYS_MATCHER = /\A\w\Z/

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
      def initialize(prompt, options = {})
        check_options_consistency(options)

        @prompt       = prompt
        @prefix       = options.fetch(:prefix) { @prompt.prefix }
        @enum         = options.fetch(:enum) { nil }
        @default      = Array[options.fetch(:default) { 1 }]
        @active       = @default.first
        @choices      = Choices.new
        @active_color = options.fetch(:active_color) { @prompt.active_color }
        @help_color   = options.fetch(:help_color) { @prompt.help_color }
        @marker       = options.fetch(:marker) { symbols[:pointer] }
        @cycle        = options.fetch(:cycle) { false }
        @filter       = options.fetch(:filter) { false } ? "" : nil
        @help         = options[:help]
        @first_render = true
        @done         = false
        @per_page     = options[:per_page]
        @page_help    = options[:page_help] || PAGE_HELP
        @paginator    = Paginator.new
        @pastel       = Pastel.new

        @prompt.subscribe(self)
      end

      # Set marker
      #
      # @api public
      def marker(value)
        @marker = value
      end

      # Set default option selected
      #
      # @api public
      def default(*default_values)
        @default = default_values
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

      # @param [String] text
      #   the help text to display per page
      # @api pbulic
      def page_help(text)
        @page_help = text
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

      # Default help text
      #
      # @api public
      def default_help
        # Note that enumeration and filter are mutually exclusive
        tokens = if enumerate?
                   [" or number (1-#{choices.size})", ""]
                 elsif @filter
                   ["", ", and letter keys to filter"]
                 else
                   ["", ""]
                 end

        format(self.class::HELP, *tokens)
      end

      # Set selecting active index using number pad
      #
      # @api public
      def enum(value)
        @enum = value
      end

      # Add a single choice
      #
      # @api public
      def choice(*value, &block)
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
          if @filter.to_s.empty?
            @choices
          else
            @choices.select do |_choice|
              _choice.name.downcase.include?(@filter.downcase)
            end
          end
        else
          Array(values).each { |val| choice(*val) }
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
        render
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
        @active = value
      end

      def keyenter(*)
        @done = true unless choices.empty?
      end
      alias keyreturn keyenter
      alias keyspace keyenter

      def keyup(*)
        if @active == 1
          @active = choices.length if @cycle
        else
          @active -= 1
        end
      end

      def keydown(*)
        if @active == choices.length
          @active = 1 if @cycle
        else
          @active += 1
        end
      end
      alias keytab keydown

      def keypress(event)
        return unless @filter

        if event.value =~ FILTER_KEYS_MATCHER
          @filter += event.value
          @active = 1
        end
      end

      def keydelete(*)
        return unless @filter

        @filter = ""
        @active = 1
      end

      def keybackspace(*)
        return unless @filter

        @filter.slice!(-1)
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
      # @api private
      def setup_defaults
        validate_defaults
        @active = @default.first
      end

      # Validate default indexes to be within range
      #
      # @api private
      def validate_defaults
        @default.each do |d|
          if d.nil? || d.to_s.empty?
            raise ConfigurationError,
                 "default index must be an integer in range (1 - #{choices.size})"
          end
          if d < 1 || d > choices.size
            raise ConfigurationError,
                 "default index `#{d}` out of range (1 - #{choices.size})"
          end
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

          @prompt.print(refresh(terminal_linecount(question_lines)))
        end
        @prompt.print(render_question)
        answer
      ensure
        @prompt.print(@prompt.show)
      end

      def terminal_linecount(lines, termwidth = TTY::Screen.width)
        lines.inject(0) do |sum, line|
          displine = @pastel.strip(line)
          linecount = 1 + [(displine.length - 1), 0].max / termwidth
          sum + linecount
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
        header = "#{@prefix}#{@question} #{render_header}\n"
        @first_render = false
        rendered_menu = render_menu
        rendered_menu << render_footer
        header << rendered_menu unless @done
        header
      end

      # Header part showing the current filter
      #
      # @return String
      #
      # @api private
      def filter_help
        "(Filter: #{@filter.inspect})"
      end

      # Render initial help and selected choice
      #
      # @return [String]
      #
      # @api private
      def render_header
        if @done
          selected_item = "#{choices[@active - 1].name}"
          @prompt.decorate(selected_item, @active_color)
        elsif @first_render
          @prompt.decorate(help, @help_color)
        elsif @filter.to_s != ""
          @prompt.decorate(filter_help, @help_color)
        end
      end

      # Render menu with choices to select from
      #
      # @return [String]
      #
      # @api private
      def render_menu
        output = ''

        @paginator.paginate(choices, @active, @per_page) do |choice, index|
          num = enumerate? ? (index + 1).to_s + @enum + ' ' : ''
          message = if index + 1 == @active
                      selected = @marker + ' ' + num + choice.name
                      @prompt.decorate("#{selected}", @active_color)
                    else
                      ' ' * 2 + num + choice.name
                    end
          max_index = paginated? ? @paginator.max_index : choices.size - 1
          newline = (index == max_index) ? '' : "\n"
          output << (message + newline)
        end

        output
      end

      # Render page info footer
      #
      # @return [String]
      #
      # @api private
      def render_footer
        return '' unless paginated?
        colored_footer = @prompt.decorate(@page_help, @help_color)
        "\n" << colored_footer
      end
    end # List
  end # Prompt
end # TTY
