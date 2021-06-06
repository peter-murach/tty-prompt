# frozen_string_literal: true

module TTY
  # A class responsible for shell prompt interactions.
  class Prompt
    # A class responsible for gathering numeric input from range
    #
    # @api public
    class Slider
      HELP = "(Use %s arrow keys, press Enter to select)"

      FORMAT = ":slider %s"

      # Initailize a Slider
      #
      # @param [Prompt] prompt
      #   the prompt
      # @param [Hash] options
      #   the options to configure this slider
      # @option options [Integer] :min The minimum value
      # @option options [Integer] :max The maximum value
      # @option options [Integer] :step The step value
      # @option options [String] :format The display format
      #
      # @api public
      def initialize(prompt, **options)
        @prompt       = prompt
        @prefix       = options.fetch(:prefix) { @prompt.prefix }
        @choices      = Choices.new
        @min          = options.fetch(:min, 0)
        @max          = options.fetch(:max, 10)
        @step         = options.fetch(:step, 1)
        @default      = options[:default]
        @active_color = options.fetch(:active_color) { @prompt.active_color }
        @help_color   = options.fetch(:help_color) { @prompt.help_color }
        @format       = options.fetch(:format) { FORMAT }
        @quiet        = options.fetch(:quiet) { @prompt.quiet }
        @help         = options[:help]
        @show_help    = options.fetch(:show_help) { :start }
        @symbols      = @prompt.symbols.merge(options.fetch(:symbols, {}))
        @first_render = true
        @done         = false
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

      # Setup initial active position
      #
      # @return [Integer]
      #
      # @api private
      def initial
        if @default.nil?
          # no default - choose the middle option
          choices.size / 2
        elsif default_choice = choices.find_by(:name, @default)
          # found a Choice by name - use it
          choices.index(default_choice)
        else
          # default is the index number
          @default - 1
        end
      end

      # Default help text
      #
      # @api public
      def default_help
        arrows = @symbols[:arrow_left] + "/" + @symbols[:arrow_right]
        sprintf(HELP, arrows)
      end

      # Set help text
      #
      # @param [String] text
      #
      # @api private
      def help(text = (not_set = true))
        return @help if !@help.nil? && not_set

        @help = (@help.nil? && not_set) ? default_help : text
      end

      # Change when help is displayed
      #
      # @api public
      def show_help(value = (not_set = true))
        return @show_help if not_set

        @show_help = value
      end

      # @api public
      def default(value)
        @default = value
      end

      # @api public
      def min(value)
        @min = value
      end

      # @api public
      def max(value)
        @max = value
      end

      # @api public
      def step(value)
        @step = value
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

      # Add multiple choices
      #
      # @param [Array[Object]] values
      #   the values to add as choices
      #
      # @api public
      def choices(values = (not_set = true))
        if not_set
          @choices
        else
          values.each { |val| @choices << val }
        end
      end

      # @api public
      def format(value)
        @format = value
      end

      # Set quiet mode.
      #
      # @api public
      def quiet(value)
        @quiet = value
      end

      # Call the slider by passing question
      #
      # @param [String] question
      #   the question to ask
      #
      # @apu public
      def call(question, possibilities = nil, &block)
        @question = question
        choices(possibilities) if possibilities
        block.call(self) if block
        # set up a Choices collection for min, max, step
        # if no possibilities were supplied
        choices((@min..@max).step(@step).to_a) if @choices.empty?

        @active = initial
        @prompt.subscribe(self) do
          render
        end
      end

      def keyleft(*)
        @active -= 1 if @active > 0
      end
      alias keydown keyleft

      def keyright(*)
        @active += 1 if (@active + 1) < choices.size
      end
      alias keyup keyright

      def keyreturn(*)
        @done = true
      end
      alias keyspace keyreturn
      alias keyenter keyreturn

      private

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

      # Render an interactive range slider.
      #
      # @api private
      def render
        @prompt.print(@prompt.hide)
        until @done
          question = render_question
          @prompt.print(question)
          @prompt.read_keypress
          refresh(question.lines.count)
        end
        @prompt.print(render_question) unless @quiet
        answer
      ensure
        @prompt.print(@prompt.show)
      end

      # Clear screen
      #
      # @param [Integer] lines
      #   the lines to clear
      #
      # @api private
      def refresh(lines)
        @prompt.print(@prompt.clear_lines(lines))
      end

      # @return [Integer, String]
      #
      # @api private
      def answer
        choices[@active].value
      end

      # Render question with the slider
      #
      # @return [String]
      #
      # @api private
      def render_question
        header = ["#{@prefix}#{@question} "]
        if @done
          header << @prompt.decorate(choices[@active].to_s, @active_color)
          header << "\n"
        else
          header << render_slider
        end
        if @first_render && (help_start? || help_always?) ||
            (help_always? && !@done)
          header << "\n" + @prompt.decorate(help, @help_color)
          @first_render = false
        end
        header.join
      end

      # Render slider representation
      #
      # @return [String]
      #
      # @api private
      def render_slider
        slider = (@symbols[:line] * @active) +
                 @prompt.decorate(@symbols[:bullet], @active_color) +
                 (@symbols[:line] * (choices.size - @active - 1))
        value = choices[@active].name
        case @format
        when Proc
          @format.call(slider, value)
        else
          @format.gsub(":slider", slider) % [value]
        end
      end
    end # Slider
  end # Prompt
end # TTY
