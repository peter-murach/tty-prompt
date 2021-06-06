# frozen_string_literal: true

RSpec.describe TTY::Prompt do
  let(:symbols) { TTY::Prompt::Symbols.symbols }
  let(:up_down) { "#{symbols[:arrow_up]}/#{symbols[:arrow_down]}" }
  let(:left_right) { "#{symbols[:arrow_left]}/#{symbols[:arrow_right]}" }
  let(:left_key) { "\e[D" }
  let(:right_key) { "\e[C" }

  subject(:prompt) { TTY::Prompt::Test.new }

  def output_helper(prompt, choices, active, selected, options = {})
    hint = options[:hint]
    init = options.fetch(:init, false)
    enum = options[:enum]

    out = []
    out << "\e[?25l" if init
    out << prompt << " "
    out << "(min. #{options[:min]}) " if options[:min]
    out << "(max. #{options[:max]}) " if options[:max]
    out << selected.join(", ")
    out << " " if (init || hint) && !selected.empty?
    out << "\e[90m(#{hint})\e[0m" if hint
    out << "\n"
    out << choices.map.with_index do |choice, i|
      name = choice.is_a?(Hash) ? choice[:name] : choice
      disabled = choice.is_a?(Hash) ? choice[:disabled] : false
      num = (i + 1).to_s + enum if enum

      prefix = name == active ? "#{symbols[:marker]} " : "  "
      prefix += if disabled
                  "\e[31m#{symbols[:cross]}\e[0m #{num}#{name} #{disabled}"
                elsif selected.include?(name)
                  "\e[32m#{symbols[:radio_on]}\e[0m #{num}#{name}"
                else
                  "#{symbols[:radio_off]} #{num}#{name}"
                end
      prefix
    end.join("\n")
    out << "\e[2K\e[1G\e[1A" * choices.count
    out << "\e[2K\e[1G"
    out.join
  end

  def exit_message(prompt, choices)
    out = []
    out << "#{prompt} "
    out << "\e[32m#{choices.join(', ')}\e[0m" unless choices.empty?
    out << "\n\e[?25h"
    out.join
  end

  # Ensure a wide prompt on CI
  before { allow(TTY::Screen).to receive(:width).and_return(200) }

  it "selects nothing when return pressed immediately" do
    choices = %i[vodka beer wine whisky bourbon]
    prompt.input << "\r"
    prompt.input.rewind

    expect(prompt.multi_select("Select drinks?", choices)).to eq([])

    expected_output =
      output_helper("Select drinks?", choices, :vodka, [], init: true,
        hint: "Press #{up_down} arrow to move, Space/Ctrl+A|R to select (all|rev) and Enter to finish") +
      exit_message("Select drinks?", [])

    expect(prompt.output.string).to eq(expected_output)
  end

  it "selects item when space pressed" do
    choices = %w[vodka beer wine whisky bourbon]
    prompt.input << " \r"
    prompt.input.rewind
    expect(prompt.multi_select("Select drinks?", choices)).to eq(["vodka"])

    expected_output =
      output_helper("Select drinks?", choices, "vodka", [], init: true,
        hint: "Press #{up_down} arrow to move, Space/Ctrl+A|R to select (all|rev) and Enter to finish") +
      output_helper("Select drinks?", choices, "vodka", ["vodka"]) +
      exit_message("Select drinks?", %w[vodka])

    expect(prompt.output.string).to eq(expected_output)
  end

  it "selects item when custom key pressed and shows custom key labels" do
    choices = %w[vodka beer wine whisky bourbon]
    prompt.input << "\C-s\r"
    prompt.input.rewind
    expect(prompt.multi_select("Select drinks?", choices, select_keys: [:ctrl_s, {escape: "Esc"}])).to eq(["vodka"])

    expected_output =
      output_helper("Select drinks?", choices, "vodka", [], init: true,
        hint: "Press #{up_down} arrow to move, Ctrl+S or Esc/Ctrl+A|R to select (all|rev) and Enter to finish") +
      output_helper("Select drinks?", choices, "vodka", ["vodka"]) +
      exit_message("Select drinks?", %w[vodka])

    expect(prompt.output.string).to eq(expected_output)
  end

  it "selects item and confirms selection with custom keys" do
    choices = %w[vodka beer wine whisky bourbon]
    prompt.input << "\C-s\e"
    prompt.input.rewind
    expect(prompt.multi_select("Select drinks?", choices, select_keys: [:ctrl_s], confirm_keys: [{escape: "Esc"}])).to eq(["vodka"])

    expected_output =
      output_helper("Select drinks?", choices, "vodka", [], init: true,
        hint: "Press #{up_down} arrow to move, Ctrl+S/Ctrl+A|R to select (all|rev) and Esc to finish") +
      output_helper("Select drinks?", choices, "vodka", ["vodka"]) +
      exit_message("Select drinks?", %w[vodka])

    expect(prompt.output.string).to eq(expected_output)
  end

  it "selects item when space pressed but doesn't echo item if echo: false" do
    choices = %w[vodka beer wine whisky bourbon]
    prompt.input << " \r"
    prompt.input.rewind
    expect(prompt.multi_select("Select drinks?", choices, echo: false)).to eq(["vodka"])

    expected_output = [
      "\e[?25lSelect drinks? \e[90m(Press #{up_down} arrow to move, Space/Ctrl+A|R to select (all|rev) and Enter to finish)\e[0m\n",
      "#{symbols[:marker]} #{symbols[:radio_off]} vodka\n",
      "  #{symbols[:radio_off]} beer\n",
      "  #{symbols[:radio_off]} wine\n",
      "  #{symbols[:radio_off]} whisky\n",
      "  #{symbols[:radio_off]} bourbon",
      "\e[2K\e[1G\e[1A" * 5, "\e[2K\e[1G",
      "Select drinks? \n",
      "#{symbols[:marker]} \e[32m#{symbols[:radio_on]}\e[0m vodka\n",
      "  #{symbols[:radio_off]} beer\n",
      "  #{symbols[:radio_off]} wine\n",
      "  #{symbols[:radio_off]} whisky\n",
      "  #{symbols[:radio_off]} bourbon",
      "\e[2K\e[1G\e[1A" * 5, "\e[2K\e[1G",
      "Select drinks? \n\e[?25h"
    ].join

    expect(prompt.output.string).to eq(expected_output)
  end

  it "sets choice custom values" do
    choices = {vodka: 1, beer: 2, wine: 3, whisky: 4, bourbon: 5}
    prompt.input << " \r"
    prompt.input.rewind

    expect(prompt.multi_select("Select drinks?", choices)).to eq([1])

    expected_output =
      output_helper("Select drinks?", choices.keys, :vodka, [], init: true,
        hint: "Press #{up_down} arrow to move, Space/Ctrl+A|R to select (all|rev) and Enter to finish") +
      output_helper("Select drinks?", choices.keys, :vodka, [:vodka]) +
      exit_message("Select drinks?", %w[vodka])

    expect(prompt.output.string).to eq(expected_output)
  end

  it "sets choice name and value through DSL" do
    prompt.input << " \r"
    prompt.input.rewind
    value = prompt.multi_select("Select drinks?") do |menu|
              menu.symbols marker: ">", radio_off: "-", radio_on: "="
              menu.enum ")"

              menu.choice :vodka, {score: 1}
              menu.choice :beer, 2
              menu.choice :wine, 3
              menu.choices whisky: 4, bourbon: 5
            end
    expect(value).to eq([{score: 1}])
    expect(prompt.output.string).to eq([
      "\e[?25lSelect drinks? \e[90m(Press #{up_down} arrow or 1-5 number to move, Space/Ctrl+A|R to select (all|rev) and Enter to finish)\e[0m\n",
      "> - 1) vodka\n",
      "  - 2) beer\n",
      "  - 3) wine\n",
      "  - 4) whisky\n",
      "  - 5) bourbon",
      "\e[2K\e[1G\e[1A" * 5, "\e[2K\e[1G",
      "Select drinks? vodka\n",
      "> \e[32m=\e[0m 1) vodka\n",
      "  - 2) beer\n",
      "  - 3) wine\n",
      "  - 4) whisky\n",
      "  - 5) bourbon",
      "\e[2K\e[1G\e[1A" * 5, "\e[2K\e[1G",
      "Select drinks? \e[32mvodka\e[0m\n\e[?25h"
    ].join)
  end

  it "sets default options through DSL syntax" do
    prompt.input << "\r"
    prompt.input.rewind
    value = prompt.multi_select("Select drinks?") do |menu|
              menu.default 2, 5

              menu.choice :vodka,   {score: 10}
              menu.choice :beer,    {score: 20}
              menu.choice :wine,    {score: 30}
              menu.choice :whisky,  {score: 40}
              menu.choice :bourbon, {score: 50}
            end
    expect(value).to match_array([{score: 20}, {score: 50}])
    expect(prompt.output.string).to eq([
      "\e[?25lSelect drinks? beer, bourbon \e[90m(Press #{up_down} arrow to move, Space/Ctrl+A|R to select (all|rev) and Enter to finish)\e[0m\n",
      "  #{symbols[:radio_off]} vodka\n",
      "  \e[32m#{symbols[:radio_on]}\e[0m beer\n",
      "  #{symbols[:radio_off]} wine\n",
      "  #{symbols[:radio_off]} whisky\n",
      "#{symbols[:marker]} \e[32m#{symbols[:radio_on]}\e[0m bourbon",
      "\e[2K\e[1G\e[1A" * 5, "\e[2K\e[1G",
      "Select drinks? \e[32mbeer, bourbon\e[0m\n\e[?25h"
    ].join)
  end

  it "sets choice value to nil through DSL" do
    choices = [
      {name: "none", value: nil},
      {name: "vodka", value: 1},
      {name: "beer", value: 1},
      {name: "wine", value: 1}
    ]
    prompt.input << "\r"
    prompt.input.rewind
    value = prompt.multi_select("Select drinks?", default: 1) do |menu|
              menu.choice :none,  nil
              menu.choice :vodka, {score: 10}
              menu.choice :beer,  {score: 20}
              menu.choice :wine,  {score: 30}
            end
    expect(value).to match_array([nil])

    expected_output =
      output_helper("Select drinks?", choices, "none", %w[none], init: true,
        hint: "Press #{up_down} arrow to move, Space/Ctrl+A|R to select " \
              "(all|rev) and Enter to finish") +
      exit_message("Select drinks?", %w[none])

    expect(prompt.output.string).to eq(expected_output)
  end

  it "sets default options through hash syntax" do
    prompt.input << "\r"
    prompt.input.rewind
    value = prompt.multi_select("Select drinks?", default: [2, 5]) do |menu|
              menu.choice :vodka,   {score: 10}
              menu.choice :beer,    {score: 20}
              menu.choice :wine,    {score: 30}
              menu.choice :whisky,  {score: 40}
              menu.choice :bourbon, {score: 50}
            end
    expect(value).to match_array([{score: 20}, {score: 50}])
  end

  it "sets default choices using names" do
    prompt.input << "\r"
    prompt.input.rewind
    value = prompt.multi_select("Select drinks?", default: [:beer, "whisky"]) do |menu|
              menu.choice :vodka,   {score: 10}
              menu.choice :beer,    {score: 20}
              menu.choice :wine,    {score: 30}
              menu.choice :whisky,  {score: 40}
              menu.choice :bourbon, {score: 50}
            end
    expect(value).to match_array([{score: 20}, {score: 40}])
  end

  it "raises error for defaults out of range" do
    prompt.input << "\r"
    prompt.input.rewind
    expect {
      prompt.multi_select("Select drinks?", default: [2, 6]) do |menu|
        menu.choice :vodka,   {score: 10}
        menu.choice :beer,    {score: 20}
        menu.choice :wine,    {score: 30}
        menu.choice :whisky,  {score: 40}
        menu.choice :bourbon, {score: 50}
      end
    }.to raise_error(TTY::Prompt::ConfigurationError,
                     /default index `6` out of range \(1 - 5\)/)
  end

  it "raises error when confirm and select keys clash (with default select_key)" do
    prompt.input << "\r"
    prompt.input.rewind
    expect {
      prompt.multi_select("Select drinks?", %w[vodka beer wine], confirm_keys: [:space])
    }.to raise_error(TTY::Prompt::ConfigurationError,
                     ":confirm_keys [:space] are conflicting with the same keys in :select_keys")
  end

  it "raises error when confirm and select keys clash (configured)" do
    prompt.input << "\r"
    prompt.input.rewind
    expect {
      prompt.multi_select("Select drinks?", %w[vodka beer wine], confirm_keys: %i[space ctrl_s], select_keys: [:space])
    }.to raise_error(TTY::Prompt::ConfigurationError,
                     ":confirm_keys [:space] are conflicting with the same keys in :select_keys")
  end


  it "sets prompt prefix" do
    prompt = TTY::Prompt::Test.new(prefix: "[?] ")
    choices = %w[vodka beer wine whisky bourbon]
    prompt.input << "\r"
    prompt.input.rewind
    expect(prompt.multi_select("Select drinks?", choices)).to eq([])
    expect(prompt.output.string).to eq([
      "\e[?25l[?] Select drinks? \e[90m(Press #{up_down} arrow to move, Space/Ctrl+A|R to select (all|rev) and Enter to finish)\e[0m\n",
      "#{symbols[:marker]} #{symbols[:radio_off]} vodka\n",
      "  #{symbols[:radio_off]} beer\n",
      "  #{symbols[:radio_off]} wine\n",
      "  #{symbols[:radio_off]} whisky\n",
      "  #{symbols[:radio_off]} bourbon",
      "\e[2K\e[1G\e[1A" * 5, "\e[2K\e[1G",
      "[?] Select drinks? \n\e[?25h"
    ].join)
  end

  it "changes selected item color & marker" do
    choices = %w[vodka beer wine whisky bourbon]
    prompt.input << "\r"
    prompt.input.rewind
    options = {default: [1], active_color: :blue, symbols: {marker: ">"}}
    expect(prompt.multi_select("Select drinks?", choices, options)).to eq(["vodka"])
    expect(prompt.output.string).to eq([
      "\e[?25lSelect drinks? vodka \e[90m(Press #{up_down} arrow to move, Space/Ctrl+A|R to select (all|rev) and Enter to finish)\e[0m\n",
      "> \e[34m#{symbols[:radio_on]}\e[0m vodka\n",
      "  #{symbols[:radio_off]} beer\n",
      "  #{symbols[:radio_off]} wine\n",
      "  #{symbols[:radio_off]} whisky\n",
      "  #{symbols[:radio_off]} bourbon",
      "\e[2K\e[1G\e[1A" * 5, "\e[2K\e[1G",
      "Select drinks? \e[34mvodka\e[0m\n\e[?25h"
    ].join)
  end

  it "changes help text and color" do
    choices = %w[vodka beer wine whisky bourbon]
    prompt.input << "\r"
    prompt.input.rewind
    options = {help: "(Bash keyboard)", help_color: :cyan}
    answer = prompt.multi_select("Select drinks?", choices, options)

    expect(answer).to eq([])
    expected_output = [
      "\e[?25lSelect drinks? \e[36m(Bash keyboard)\e[0m\n",
      "#{symbols[:marker]} #{symbols[:radio_off]} vodka\n",
      "  #{symbols[:radio_off]} beer\n",
      "  #{symbols[:radio_off]} wine\n",
      "  #{symbols[:radio_off]} whisky\n",
      "  #{symbols[:radio_off]} bourbon",
      "\e[2K\e[1G\e[1A" * 5, "\e[2K\e[1G",
      "Select drinks? \n\e[?25h"
    ].join

    expect(prompt.output.string).to eq(expected_output)
  end

  it "sets prompt to quiet mode" do
    prompt = TTY::Prompt::Test.new(quiet: true)
    choices = %w[vodka beer wine whisky bourbon]
    prompt.input << "\r"
    prompt.input.rewind

    expect(prompt.multi_select("Select drinks?", choices)).to eq([])

    expected_output =
      output_helper("Select drinks?", choices, "vodka", [], init: true,
        hint: "Press #{up_down} arrow to move, Space/Ctrl+A|R to select (all|rev) and Enter to finish") +
      "\e[?25h"
    expect(prompt.output.string).to eq(expected_output)
  end

  it "changes to always show help" do
    choices = %w[vodka beer wine whisky bourbon]
    prompt.on(:keypress) { |e| prompt.trigger(:keydown) if e.value == "j" }
    prompt.input << "j" << "j" << " " << "\r"
    prompt.input.rewind

    answer = prompt.multi_select("Select drinks?", choices, show_help: :always)
    expect(answer).to eq(%w[wine])

    expected_output =
      output_helper("Select drinks?", choices, "vodka", [], init: true,
        hint: "Press #{up_down} arrow to move, Space/Ctrl+A|R to select " \
              "(all|rev) and Enter to finish") +
      output_helper("Select drinks?", choices, "beer", [],
        hint: "Press #{up_down} arrow to move, Space/Ctrl+A|R to select " \
              "(all|rev) and Enter to finish") +
      output_helper("Select drinks?", choices, "wine", [],
        hint: "Press #{up_down} arrow to move, Space/Ctrl+A|R to select " \
              "(all|rev) and Enter to finish") +
      output_helper("Select drinks?", choices, "wine", %w[wine],
        hint: "Press #{up_down} arrow to move, Space/Ctrl+A|R to select " \
              "(all|rev) and Enter to finish") +
      exit_message("Select drinks?", %w[wine])

    expect(prompt.output.string).to eq(expected_output)
  end

  it "changes to never show help" do
    choices = %w[vodka beer wine whisky bourbon]
    prompt.on(:keypress) { |e| prompt.trigger(:keydown) if e.value == "j" }
    prompt.input << "j" << "j" << " " << "\r"
    prompt.input.rewind

    answer = prompt.multi_select("Select drinks?", choices, show_help: :never)
    expect(answer).to eq(%w[wine])

    expected_output =
      output_helper("Select drinks?", choices, "vodka", [], init: true) +
      output_helper("Select drinks?", choices, "beer", []) +
      output_helper("Select drinks?", choices, "wine", []) +
      output_helper("Select drinks?", choices, "wine", %w[wine]) +
      exit_message("Select drinks?", %w[wine])

    expect(prompt.output.string).to eq(expected_output)
  end

  context "when paginated" do
    it "paginates long selections" do
      choices = %w[A B C D E F G H]
      prompt.input << "\r"
      prompt.input.rewind

      answer = prompt.multi_select("What letter?", choices, per_page: 3, default: 4)
      expect(answer).to eq(["D"])

      expected_output =
        output_helper("What letter?", choices[3..5], "D", %w[D], init: true,
          hint: "Press #{up_down}/#{left_right} arrow to move, Space/Ctrl+A|R to select (all|rev) and Enter to finish") +
        exit_message("What letter?", %w[D])

      expect(prompt.output.string).to eq(expected_output)
    end

    it "paginates choices as hash object" do
      choices = {A: 1, B: 2, C: 3, D: 4, E: 5, F: 6, G: 7, H: 8}
      prompt.input << "\r"
      prompt.input.rewind

      answer = prompt.multi_select("What letter?", choices, default: 4, per_page: 3)
      expect(answer).to eq([4])

      expected_output =
        output_helper("What letter?", choices.keys[3..5], :D, [:D], init: true,
          hint: "Press #{up_down}/#{left_right} arrow to move, Space/Ctrl+A|R to select (all|rev) and Enter to finish") +
        exit_message("What letter?", %w[D])

      expect(prompt.output.string).to eq(expected_output)
    end

    it "paginates long selections through DSL" do
      choices = %w[A B C D E F G H]
      prompt.input << "\r"
      prompt.input.rewind

      answer = prompt.multi_select("What letter?") do |menu|
                menu.per_page 3
                menu.default 4
                menu.choices choices
              end
      expect(answer).to eq(["D"])

      expected_output =
        output_helper("What letter?", choices[3..5], "D", %w[D], init: true,
          hint: "Press #{up_down}/#{left_right} arrow to move, Space/Ctrl+A|R to select (all|rev) and Enter to finish") +
        exit_message("What letter?", %w[D])

      expect(prompt.output.string).to eq(expected_output)
    end

    it "doesn't paginate short selections" do
      choices = %w[A B C D]
      prompt.input << "\r"
      prompt.input.rewind

      value = prompt.multi_select("What letter?", choices, per_page: 4, default: 1)
      expect(value).to eq(["A"])

      expected_output =
        output_helper("What letter?", choices, "A", %w[A], init: true,
          hint: "Press #{up_down} arrow to move, Space/Ctrl+A|R to select (all|rev) and Enter to finish") +
        exit_message("What letter?", %w[A])

      expect(prompt.output.string).to eq(expected_output)
    end

    it "navigates evenly paged output with right arrow until end of selection" do
      choices = ("1".."12").to_a
      prompt.on(:keypress) { |e| prompt.trigger(:keyright) if e.value == "l" }
      prompt.input << "l" << "l" << "l" << " " << "\r"
      prompt.input.rewind

      answer = prompt.multi_select("What number?", choices, per_page: 4)

      expect(answer).to eq(["9"])

      expected_output =
        output_helper("What number?", choices[0..3], "1", [], init: true,
          hint: "Press #{up_down}/#{left_right} arrow to move, Space/Ctrl+A|R to select (all|rev) and Enter to finish") +
        output_helper("What number?", choices[4..7], "5", []) +
        output_helper("What number?", choices[8..11], "9", []) +
        output_helper("What number?", choices[8..11], "9", []) +
        output_helper("What number?", choices[8..11], "9", ["9"]) +
        exit_message("What number?", %w[9])

      expect(prompt.output.string).to eq(expected_output)
    end

    it "navigates unevenly paged output with right arrow until the end of selection" do
      choices = ("1".."10").to_a
      prompt.on(:keypress) { |e| prompt.trigger(:keyright) if e.value == "l" }
      prompt.input << "l" << "l" << "l" << " " << "\r"
      prompt.input.rewind

      answer = prompt.multi_select("What number?", choices, default: 4, per_page: 4)

      expect(answer).to eq(%w[4 10])

      expected_output =
        output_helper("What number?", choices[3..6], "4", ["4"], init: true,
          hint: "Press #{up_down}/#{left_right} arrow to move, Space/Ctrl+A|R to select (all|rev) and Enter to finish") +
        output_helper("What number?", choices[4..7], "8", ["4"]) +
        output_helper("What number?", choices[8..9], "10", ["4"]) +
        output_helper("What number?", choices[8..9], "10", ["4"]) +
        output_helper("What number?", choices[8..9], "10", %w[4 10]) +
        exit_message("What number?", %w[4 10])

      expect(prompt.output.string).to eq(expected_output)
    end

    it "navigates left and right" do
      choices = ("1".."10").to_a
      prompt.on(:keypress) { |e|
        prompt.trigger(:keyright) if e.value == "l"
        prompt.trigger(:keyleft) if e.value == "h"
      }
      prompt.input << "l" << "l" << "h" << " " << "\r"
      prompt.input.rewind

      answer = prompt.multi_select("What number?", choices, default: 2, per_page: 4)

      expect(answer).to eq(%w[2 6])

      expected_output =
        output_helper("What number?", choices[0..3], "2", ["2"], init: true,
          hint: "Press #{up_down}/#{left_right} arrow to move, Space/Ctrl+A|R to select (all|rev) and Enter to finish") +
        output_helper("What number?", choices[4..7], "6", ["2"]) +
        output_helper("What number?", choices[8..9], "10", ["2"]) +
        output_helper("What number?", choices[4..7], "6", ["2"]) +
        output_helper("What number?", choices[4..7], "6", %w[2 6]) +
        exit_message("What number?", %w[2 6])

      expect(prompt.output.string).to eq(expected_output)
    end

    it "combines up/down navigation with left/right" do
      choices = ("1".."11").to_a
      prompt.on(:keypress) { |e|
        prompt.trigger(:keyup)    if e.value == "k"
        prompt.trigger(:keydown)  if e.value == "j"
        prompt.trigger(:keyright) if e.value == "l"
        prompt.trigger(:keyleft)  if e.value == "h"
      }
      prompt.input << "j" << "l" << "k" << "k" << "h" << " " << "\r"
      prompt.input.rewind

      answer = prompt.multi_select("What number?", choices, default: 2, per_page: 4)

      expect(answer).to eq(%w[1 2])

      expected_output =
        output_helper("What number?", choices[0..3], "2", ["2"], init: true,
          hint: "Press #{up_down}/#{left_right} arrow to move, Space/Ctrl+A|R to select (all|rev) and Enter to finish") +
        output_helper("What number?", choices[0..3], "3", ["2"]) +
        output_helper("What number?", choices[4..7], "7", ["2"]) +
        output_helper("What number?", choices[4..7], "6", ["2"]) +
        output_helper("What number?", choices[3..6], "5", ["2"]) +
        output_helper("What number?", choices[0..3], "1", ["2"]) +
        output_helper("What number?", choices[0..3], "1", %w[1 2]) +
        exit_message("What number?", %w[1 2])

      expect(prompt.output.string).to eq(expected_output)
    end

    it "selects all paged choices with ctrl+a" do
      choices = ("1".."12").to_a
      prompt.on(:keypress) { |e| prompt.trigger(:keyctrl_a) if e.value == "a" }
      prompt.input << "a" << " " << "\r"
      prompt.input.rewind

      answer = prompt.multi_select("What number?", choices, per_page: 4)

      expect(answer).to eq(choices - %w[1])

      expected_output =
        output_helper("What number?", choices[0..3], "1", [], init: true,
          hint: "Press #{up_down}/#{left_right} arrow to move, Space/Ctrl+A|R to select (all|rev) and Enter to finish") +
        output_helper("What number?", choices[0..3], "1", choices) +
        output_helper("What number?", choices[0..3], "1", choices - %w[1]) +
        exit_message("What number?", choices - %w[1])

      expect(prompt.output.string).to eq(expected_output)
    end

    it "reverts selection accross pages with Ctrl+r" do
      choices = ("1".."12").to_a
      prompt.on(:keypress) { |e|
        prompt.trigger(:keyctrl_r) if e.value == "r"
        prompt.trigger(:keydown) if e.value == "j"
      }
      prompt.input << " " << "j" << " " << "j" << " " << "r" << "\r"
      prompt.input.rewind

      answer = prompt.multi_select("What number?", choices, per_page: 4)

      expect(answer).to eq(("4".."12").to_a)

      expected_output =
        output_helper("What number?", choices[0..3], "1", [], init: true,
          hint: "Press #{up_down}/#{left_right} arrow to move, Space/Ctrl+A|R to select (all|rev) and Enter to finish") +
        output_helper("What number?", choices[0..3], "1", ["1"]) +
        output_helper("What number?", choices[0..3], "2", ["1"]) +
        output_helper("What number?", choices[0..3], "2", %w[1 2]) +
        output_helper("What number?", choices[0..3], "3", %w[1 2]) +
        output_helper("What number?", choices[0..3], "3", %w[1 2 3]) +
        output_helper("What number?", choices[0..3], "3", ("4".."12").to_a) +
        exit_message("What number?", ("4".."12").to_a)

      expect(prompt.output.string).to eq(expected_output)
    end
  end

  context "with :cycle" do
    it "doesn't cycle by default" do
      choices = %w[A B C]
      prompt.on(:keypress) { |e| prompt.trigger(:keydown) if e.value == "j" }
      prompt.input << "j" << "j" << "j" << " " << "\r"
      prompt.input.rewind

      value = prompt.multi_select("What letter?", choices)
      expect(value).to eq(["C"])

      expected_output =
        output_helper("What letter?", choices, "A", [], init: true,
          hint: "Press #{up_down} arrow to move, Space/Ctrl+A|R to select (all|rev) and Enter to finish") +
        output_helper("What letter?", choices, "B", []) +
        output_helper("What letter?", choices, "C", []) +
        output_helper("What letter?", choices, "C", []) +
        output_helper("What letter?", choices, "C", ["C"]) +
        exit_message("What letter?", %w[C])

      expect(prompt.output.string).to eq(expected_output)
    end

    it "cycles when configured to do so" do
      choices = %w[A B C]
      prompt.on(:keypress) { |e| prompt.trigger(:keydown) if e.value == "j" }
      prompt.input << "j" << "j" << "j" << " " << "\r"
      prompt.input.rewind

      value = prompt.multi_select("What letter?", choices, cycle: true)
      expect(value).to eq(["A"])

      expected_output =
        output_helper("What letter?", choices, "A", [], init: true,
          hint: "Press #{up_down} arrow to move, Space/Ctrl+A|R to select (all|rev) and Enter to finish") +
        output_helper("What letter?", choices, "B", []) +
        output_helper("What letter?", choices, "C", []) +
        output_helper("What letter?", choices, "A", []) +
        output_helper("What letter?", choices, "A", ["A"]) +
        exit_message("What letter?", %w[A])

      expect(prompt.output.string).to eq(expected_output)
    end

    it "cycles choices using left/right arrows" do
      choices = ("1".."10").to_a
      prompt.on(:keypress) { |e|
        prompt.trigger(:keyright) if e.value == "l"
        prompt.trigger(:keyleft) if e.value == "h"
      }
      prompt.input << "l" << "l" << "l" << "h" << " " << "\r"
      prompt.input.rewind

      answer = prompt.multi_select("What number?", choices, default: 2, per_page: 4, cycle: true)

      expect(answer).to eq(%w[2 10])

      expected_output =
        output_helper("What number?", choices[0..3], "2", %w[2], init: true,
          hint: "Press #{up_down}/#{left_right} arrow to move, Space/Ctrl+A|R to select (all|rev) and Enter to finish") +
        output_helper("What number?", choices[4..7], "6", %w[2]) +
        output_helper("What number?", choices[8..9], "10", %w[2]) +
        output_helper("What number?", choices[0..3], "2", %w[2]) +
        output_helper("What number?", choices[8..9], "10", %w[2]) +
        output_helper("What number?", choices[8..9], "10", %w[2 10]) +
        exit_message("What number?", %w[2 10])

      expect(prompt.output.string).to eq(expected_output)
    end

    it "cycles filtered choices left and right" do
      numbers = ("1".."10").to_a
      choices = numbers.map { |n| "a#{n}" } + numbers.map { |n| "b#{n}" }
      prompt.input << "b" << right_key << right_key << right_key
      prompt.input << left_key << left_key << left_key << " \r"
      prompt.input.rewind

      answer = prompt.multi_select("What room?", choices, default: 2, per_page: 4,
                                                          filter: true, cycle: true)

      expect(answer).to eq(%w[a2 b2])

      expected_output =
        output_helper("What room?", choices[0..3], "a2", %w[a2], init: true,
          hint: "Press #{up_down}/#{left_right} arrow to move, Space/Ctrl+A|R to select (all|rev), Enter to finish and letters to filter") +
        output_helper("What room?", choices[10..13], "b1", %w[a2], hint: "Filter: \"b\"") +
        output_helper("What room?", choices[14..17], "b5", %w[a2], hint: "Filter: \"b\"") +
        output_helper("What room?", choices[18..20], "b9", %w[a2], hint: "Filter: \"b\"") +
        output_helper("What room?", choices[10..13], "b1", %w[a2], hint: "Filter: \"b\"") +
        output_helper("What room?", choices[18..20], "b10", %w[a2], hint: "Filter: \"b\"") +
        output_helper("What room?", choices[14..17], "b6", %w[a2], hint: "Filter: \"b\"") +
        output_helper("What room?", choices[10..13], "b2", %w[a2], hint: "Filter: \"b\"") +
        output_helper("What room?", choices[10..13], "b2", %w[a2 b2], hint: "Filter: \"b\"") +
        exit_message("What room?", %w[a2 b2])

      expect(prompt.output.string).to eq(expected_output)
    end
  end

  context "with filter" do
    it "doesn't lose the selection when switching between filters" do
      choices = %w[Tiny Medium Large Huge]
      prompt.on(:keypress) { |e| prompt.trigger(:keydelete) if e.value == "\r" }
      prompt.input << " "         # select `Tiny`
      prompt.input << "a" << " "  # match and select `Large`
      prompt.input << "\u007F"    # backspace (shows all)
      prompt.input << "\r"
      prompt.input.rewind

      answer = prompt.multi_select("What size?", choices, filter: true, show_help: :always)
      expect(answer).to eql(%w[Tiny Large])

      expected_output =
        output_helper("What size?", %w[Tiny Medium Large Huge], "Tiny", %w[], init: true,
          hint: "Press #{up_down} arrow to move, Space/Ctrl+A|R to select (all|rev), Enter to finish and letters to filter") +
        output_helper("What size?", %w[Tiny Medium Large Huge], "Tiny", %w[Tiny],
          hint: "Press #{up_down} arrow to move, Space/Ctrl+A|R to select (all|rev), Enter to finish and letters to filter") +
        output_helper("What size?", %w[Large], "Large", %w[Tiny], hint: "Filter: \"a\"") +
        output_helper("What size?", %w[Large], "Large", %w[Tiny Large], hint: "Filter: \"a\"") +
        output_helper("What size?", %w[Tiny Medium Large Huge], "Tiny", %w[Tiny Large],
          hint: "Press #{up_down} arrow to move, Space/Ctrl+A|R to select (all|rev), Enter to finish and letters to filter") +
        exit_message("What size?", %w[Tiny Large])

      expect(prompt.output.string).to eql(expected_output)
    end

    it "continues filtering when space is pressed with custom select key" do
      choices = ["gin", "gin fizz", "gin tonic"]
      prompt.input << "gin"
      prompt.input << " "
      prompt.input << "f"
      prompt.input << "\C-s"
      prompt.input << "\u007F"  # Delete one letter
      prompt.input << "t"
      prompt.input << "\C-s"
      prompt.input << "\r"
      prompt.input.rewind

      expect(prompt.multi_select("Select drinks?", choices, filter: true, select_keys: [:ctrl_s])).to eq(["gin fizz", "gin tonic"])

      expected_output =
        output_helper("Select drinks?", choices, "gin", [], init: true,
          hint: "Press #{up_down} arrow to move, Ctrl+S/Ctrl+A|R to select (all|rev), Enter to finish and letters to filter") +
        output_helper("Select drinks?", choices, "gin", [], hint: "Filter: \"g\"") +
        output_helper("Select drinks?", choices, "gin", [], hint: "Filter: \"gi\"") +
        output_helper("Select drinks?", choices, "gin", [], hint: "Filter: \"gin\"") +
        output_helper("Select drinks?", ["gin fizz", "gin tonic"], "gin fizz", [], hint: "Filter: \"gin \"") +
        output_helper("Select drinks?", ["gin fizz"], "gin fizz", [], hint: "Filter: \"gin f\"") +
        output_helper("Select drinks?", ["gin fizz"], "gin fizz", ["gin fizz"], hint: "Filter: \"gin f\"") +
        output_helper("Select drinks?", ["gin fizz", "gin tonic"], "gin fizz", ["gin fizz"], hint: "Filter: \"gin \"") +
        output_helper("Select drinks?", ["gin tonic"], "gin tonic", ["gin fizz"], hint: "Filter: \"gin t\"") +
        output_helper("Select drinks?", ["gin tonic"], "gin tonic", ["gin fizz", "gin tonic"], hint: "Filter: \"gin t\"") +
        exit_message("Select drinks?", ["gin fizz", "gin tonic"])

      expect(prompt.output.string).to eq(expected_output)
    end
  end

  context "with :disabled" do
    it "fails when default item is also disabled" do
      choices = [
        {name: "vodka", disabled: true},
        "beer", "wine", "whisky", "bourbon"
      ]
      expect {
        prompt.multi_select("Select drinks?", choices, default: 1)
      }.to raise_error(TTY::Prompt::ConfigurationError,
                       "default index `1` matches disabled choice")
    end

    it "adjusts active index to match first non-disabled choice" do
      choices = [
        {name: "vodka", disabled: true},
        "beer", "wine", "whisky", "bourbon"
      ]
      prompt.input << " " << "\r"
      prompt.input.rewind

      answer = prompt.multi_select("Select drinks?", choices)
      expect(answer).to eq(["beer"])
    end

    it "omits disabled choice when nagivating menu" do
      choices = [
        {name: "A"},
        {name: "B", disabled: "(out)"},
        {name: "C", disabled: "(out)"},
        {name: "D"},
        {name: "E"}
      ]
      prompt.on(:keypress) { |e| prompt.trigger(:keydown) if e.value == "j" }
      prompt.input << "j" << " " << "j" << " " << "\r"
      prompt.input.rewind

      answer = prompt.multi_select("What letter?", choices)
      expect(answer).to eq(%w[D E])

      expected_output =
        output_helper("What letter?", choices, "A", [], init: true,
          hint: "Press #{up_down} arrow to move, Space/Ctrl+A|R to select (all|rev) and Enter to finish") +
        output_helper("What letter?", choices, "D", []) +
        output_helper("What letter?", choices, "D", %w[D]) +
        output_helper("What letter?", choices, "E", %w[D]) +
        output_helper("What letter?", choices, "E", %w[D E]) +
        exit_message("What letter?", %w[D E])

      expect(prompt.output.string).to eq(expected_output)
    end

    it "omits disabled choice when number key is pressed" do
      choices = [
        {name: "vodka", value: 1},
        {name: "beer", value: 1, disabled: true},
        {name: "wine", value: 1},
        {name: "whisky", value: 1, disabled: true},
        {name: "bourbon", value: 1}
      ]
      prompt.input << "2" << " \r"
      prompt.input.rewind
      answer = prompt.multi_select("Select drinks?") do |menu|
                menu.enum ")"

                menu.choice :vodka, 1
                menu.choice :beer, 2, disabled: true
                menu.choice :wine, 3
                menu.choice :whisky, 4, disabled: true
                menu.choice :bourbon, 5
              end
      expect(answer).to eq([1])

      expected_output =
        output_helper("Select drinks?", choices, "vodka", [], init: true, enum: ") ",
          hint: "Press #{up_down} arrow or 1-5 number to move, Space/Ctrl+A|R to select (all|rev) and Enter to finish") +
        output_helper("Select drinks?", choices, "vodka", [], enum: ") ") +
        output_helper("Select drinks?", choices, "vodka", %w[vodka], enum: ") ") +
        exit_message("Select drinks?", %w[vodka])

      expect(prompt.output.string).to eq(expected_output)
    end

    it "selects all non-disabled choices when ctrl+a is pressed" do
      choices = [
        {name: "A"},
        {name: "B", disabled: "(out)"},
        {name: "C", disabled: "(out)"},
        {name: "D"},
        {name: "E"}
      ]
      prompt.on(:keypress) { |e|
        prompt.trigger(:keyctrl_a) if e.value == "a"
        prompt.trigger(:keyctrl_r) if e.value == "r"
      }
      prompt.input << "a" << "r" << "a" << "\r"
      prompt.input.rewind

      answer = prompt.multi_select("What letter?", choices)
      expect(answer).to eq(%w[A D E])

      expected_output =
        output_helper("What letter?", choices, "A", [], init: true,
          hint: "Press #{up_down} arrow to move, Space/Ctrl+A|R to select (all|rev) and Enter to finish") +
        output_helper("What letter?", choices, "A", %w[A D E]) +
        output_helper("What letter?", choices, "A", %w[]) +
        output_helper("What letter?", choices, "A", %w[A D E]) +
        exit_message("What letter?", %w[A D E])

      expect(prompt.output.string).to eq(expected_output)
    end
  end

  context "with :min" do
    it "requires number of choices" do
      choices = %w[A B C]
      prompt.on(:keypress) { |e|
        prompt.trigger(:keydown) if e.value == "j"
      }
      prompt.input << " " << "\r" << "j" << " " << "\r"
      prompt.input.rewind

      value = prompt.multi_select("What letter?", choices, min: 2, per_page: 100)
      expect(value).to eq(%w[A B])

      expected_output =
        output_helper("What letter?", choices, "A", [], init: true, min: 2,
          hint: "Press #{up_down} arrow to move, Space/Ctrl+A|R to select (all|rev) and Enter to finish") +
        output_helper("What letter?", choices, "A", %w[A], min: 2) +
        output_helper("What letter?", choices, "A", %w[A], min: 2) +
        output_helper("What letter?", choices, "B", %w[A], min: 2) +
        output_helper("What letter?", choices, "B", %w[A B], min: 2) +
        exit_message("What letter?", %w[A B])

      expect(prompt.output.string).to eq(expected_output)
    end
  end

  context "with :max" do
    it "limits number of choices" do
      choices = %w[A B C]
      prompt.on(:keypress) { |e|
        prompt.trigger(:keyup)   if e.value == "k"
        prompt.trigger(:keydown) if e.value == "j"
      }
      prompt.input << " " << "j" << " " << "j" << " " << "k" << " " << "j" << " " << "\r"
      prompt.input.rewind

      value = prompt.multi_select("What letter?", choices, max: 2, per_page: 100)
      expect(value).to eq(%w[A C])

      expected_output =
        output_helper("What letter?", choices, "A", [], init: true, max: 2,
          hint: "Press #{up_down} arrow to move, Space to select and Enter to finish") +
        output_helper("What letter?", choices, "A", %w[A], max: 2) +
        output_helper("What letter?", choices, "B", %w[A], max: 2) +
        output_helper("What letter?", choices, "B", %w[A B], max: 2) +
        output_helper("What letter?", choices, "C", %w[A B], max: 2) +
        output_helper("What letter?", choices, "C", %w[A B], max: 2) +
        output_helper("What letter?", choices, "B", %w[A B], max: 2) +
        output_helper("What letter?", choices, "B", %w[A], max: 2) +
        output_helper("What letter?", choices, "C", %w[A], max: 2) +
        output_helper("What letter?", choices, "C", %w[A C], max: 2) +
        exit_message("What letter?", %w[A C])

      expect(prompt.output.string).to eq(expected_output)
    end

    it "disables Ctrl+a/Ctrl+r selection when :max option is specified" do
      choices = %w[A B C D E F G]
      prompt.on(:keypress) { |e|
        prompt.trigger(:keyctrl_a) if e.value == "a"
        prompt.trigger(:keyctrl_r) if e.value == "r"
        prompt.trigger(:keydown) if e.value == "j"
      }
      prompt.input << "a" << "j" << " " << "r" << "j" << " " << "\r"
      prompt.input.rewind

      value = prompt.multi_select("What letter?", choices, max: 2, per_page: 100)
      expect(value).to eq(%w[B C])

      expected_output =
        output_helper("What letter?", choices, "A", [], init: true, max: 2,
          hint: "Press #{up_down} arrow to move, Space to select and Enter to finish") +
        output_helper("What letter?", choices, "A", %w[], max: 2) +
        output_helper("What letter?", choices, "B", %w[], max: 2) +
        output_helper("What letter?", choices, "B", %w[B], max: 2) +
        output_helper("What letter?", choices, "B", %w[B], max: 2) +
        output_helper("What letter?", choices, "C", %w[B], max: 2) +
        output_helper("What letter?", choices, "C", %w[B C], max: 2) +
        exit_message("What letter?", %w[B C])

      expect(prompt.output.string).to eq(expected_output)
    end
  end
end
