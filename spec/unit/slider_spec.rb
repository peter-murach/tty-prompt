# frozen_string_literal: true

RSpec.describe TTY::Prompt, "#slider" do
  subject(:prompt) { TTY::Prompt::Test.new }

  let(:symbols) { TTY::Prompt::Symbols.symbols }
  let(:left_right) { "#{symbols[:arrow_left]}/#{symbols[:arrow_right]}"}

  it "specifies ranges & step" do
    prompt.input << "\r"
    prompt.input.rewind
    expect(prompt.slider("What size?", min: 32, max: 54, step: 2)).to eq(44)
    expect(prompt.output.string).to eq([
      "\e[?25lWhat size? ",
      symbols[:line] * 6,
      "\e[32m#{symbols[:bullet]}\e[0m",
      "#{symbols[:line] * 5} 44",
      "\n\e[90m(Use #{left_right} arrow keys, press Enter to select)\e[0m",
      "\e[2K\e[1G\e[1A\e[2K\e[1G",
      "What size? \e[32m44\e[0m\n\e[?25h"
    ].join)
  end

  it "specifies default value" do
    prompt.input << "\r"
    prompt.input.rewind
    expect(prompt.slider("What size?", min: 32, max: 54, step: 2, default: 38)).to eq(38)
    expect(prompt.output.string).to eq([
      "\e[?25lWhat size? ",
      symbols[:line] * 3,
      "\e[32m#{symbols[:bullet]}\e[0m",
      "#{symbols[:line] * 8} 38",
      "\n\e[90m(Use #{left_right} arrow keys, press Enter to select)\e[0m",
      "\e[2K\e[1G\e[1A\e[2K\e[1G",
      "What size? \e[32m38\e[0m\n\e[?25h"
    ].join)
  end

  it "specifies range through DSL" do
    prompt.input << "\r"
    prompt.input.rewind
    value = prompt.slider("What size?") do |range|
              range.help "(Move with arrows)"
              range.default 6
              range.min 0
              range.max 20
              range.step 2
              range.format "|:slider| %d%%"
            end
    expect(value).to eq(6)
    expect(prompt.output.string).to eq([
      "\e[?25lWhat size? ",
      symbols[:pipe] + symbols[:line] * 3,
      "\e[32m#{symbols[:bullet]}\e[0m",
      "#{symbols[:line] * 7 + symbols[:pipe]} 6%",
      "\n\e[90m(Move with arrows)\e[0m",
      "\e[2K\e[1G\e[1A\e[2K\e[1G",
      "What size? \e[32m6\e[0m\n\e[?25h"
    ].join)
  end

  it "formats via proc" do
    prompt.input << "\r"
    prompt.input.rewind
    value = prompt.slider("What size?") do |range|
              range.default 6
              range.max 20
              range.step 2
              range.format ->(slider, value) { "|#{slider}| %d%%" % value }
            end
    expect(value).to eq(6)
    expect(prompt.output.string).to eq([
      "\e[?25lWhat size? ",
      symbols[:pipe] + symbols[:line] * 3,
      "\e[32m#{symbols[:bullet]}\e[0m",
      "#{symbols[:line] * 7 + symbols[:pipe]} 6%",
      "\n\e[90m(Use #{left_right} arrow keys, press Enter to select)\e[0m",
      "\e[2K\e[1G\e[1A\e[2K\e[1G",
      "What size? \e[32m6\e[0m\n\e[?25h"
    ].join)
  end

  it "changes display colors" do
    prompt.input << "\r"
    prompt.input.rewind
    options = {active_color: :red, help_color: :cyan}
    expect(prompt.slider("What size?", **options)).to eq(5)
    expect(prompt.output.string).to eq([
      "\e[?25lWhat size? ",
      symbols[:line] * 5,
      "\e[31m#{symbols[:bullet]}\e[0m",
      "#{symbols[:line] * 5} 5",
      "\n\e[36m(Use #{left_right} arrow keys, press Enter to select)\e[0m",
      "\e[2K\e[1G\e[1A\e[2K\e[1G",
      "What size? \e[31m5\e[0m\n\e[?25h"
    ].join)
  end

  it "doesn't allow values outside of range" do
    prompt.input << "l\r"
    prompt.input.rewind
    prompt.on(:keypress) do |event|
      if event.value = "l"
        prompt.trigger(:keyright)
      end
    end
    res = prompt.slider("What size?", min: 0, max: 10, step: 1, default: 10)
    expect(res).to eq(10)
    expect(prompt.output.string).to eq([
      "\e[?25lWhat size? ",
      symbols[:line] * 10,
      "\e[32m#{symbols[:bullet]}\e[0m 10",
      "\n\e[90m(Use #{left_right} arrow keys, press Enter to select)\e[0m",
      "\e[2K\e[1G\e[1A\e[2K\e[1G",
      "What size? ",
      symbols[:line] * 10,
      "\e[32m#{symbols[:bullet]}\e[0m 10",
      "\e[2K\e[1G",
      "What size? \e[32m10\e[0m\n\e[?25h"
    ].join)
  end

  it "changes all display symbols" do
    prompt = TTY::Prompt::Test.new(symbols: {
      bullet: "x",
      line: "_"
    })
    prompt.input << "\r"
    prompt.input.rewind

    expect(prompt.slider("What size?", min: 32, max: 54, step: 2)).to eq(44)

    expect(prompt.output.string).to eq([
      "\e[?25lWhat size? ",
      "_" * 6,
      "\e[32mx\e[0m",
      "#{"_" * 5} 44",
      "\n\e[90m(Use #{left_right} arrow keys, press Enter to select)\e[0m",
      "\e[2K\e[1G\e[1A\e[2K\e[1G",
      "What size? \e[32m44\e[0m\n\e[?25h"
    ].join)
  end

  it "changes all display symbols per instance" do
    prompt.input << "\r"
    prompt.input.rewind

    answer = prompt.slider("What size?", min: 32, max: 54, step: 2) do |range|
      range.symbols bullet: "x", line: "_"
    end

    expect(answer).to eq(44)
    expect(prompt.output.string).to eq([
      "\e[?25lWhat size? ",
      "_" * 6,
      "\e[32mx\e[0m",
      "#{"_" * 5} 44",
      "\n\e[90m(Use #{left_right} arrow keys, press Enter to select)\e[0m",
      "\e[2K\e[1G\e[1A\e[2K\e[1G",
      "What size? \e[32m44\e[0m\n\e[?25h"
    ].join)
  end

  it "sets quiet mode" do
    prompt.input << "\r"
    prompt.input.rewind
    expect(prompt.slider("What size?", min: 32, max: 54, step: 2, quiet: true)).to eq(44)
    expect(prompt.output.string).to eq([
      "\e[?25lWhat size? ",
      symbols[:line] * 6,
      "\e[32m#{symbols[:bullet]}\e[0m",
      "#{symbols[:line] * 5} 44",
      "\n\e[90m(Use #{left_right} arrow keys, press Enter to select)\e[0m",
      "\e[2K\e[1G\e[1A\e[2K\e[1G",
      "\e[?25h"
    ].join)
  end

  it "specifies quiet mode through DSL" do
    prompt.input << "\r"
    prompt.input.rewind
    value = prompt.slider("What size?") do |slider|
              slider.quiet true
              slider.default 6
              slider.min 0
              slider.max 20
              slider.step 2
              slider.format "|:slider| %d%%"
            end
    expect(value).to eq(6)
    expect(prompt.output.string).to eq([
      "\e[?25lWhat size? ",
      symbols[:pipe] + symbols[:line] * 3,
      "\e[32m#{symbols[:bullet]}\e[0m",
      "#{symbols[:line] * 7 + symbols[:pipe]} 6%",
      "\n\e[90m(Use #{left_right} arrow keys, press Enter to select)\e[0m",
      "\e[2K\e[1G\e[1A\e[2K\e[1G",
      "\e[?25h"
    ].join)
  end

  it "changes to always show help" do
    prompt.on(:keypress) do |event|
      prompt.trigger(:keyright) if event.value == "l"
    end
    prompt.input << "l" << "l" << "\r"
    prompt.input.rewind

    res = prompt.slider("What size?", min: 0, max: 10, step: 1,
                        default: 0, show_help: :always)
    expect(res).to eq(2)

    expected_output = [
      "\e[?25lWhat size? ",
      "\e[32m#{symbols[:bullet]}\e[0m",
      symbols[:line] * 10 + " 0",
      "\n\e[90m(Use #{left_right} arrow keys, press Enter to select)\e[0m",
      "\e[2K\e[1G\e[1A\e[2K\e[1G",
      "What size? ",
      symbols[:line] * 1,
      "\e[32m#{symbols[:bullet]}\e[0m",
      symbols[:line] * 9 + " 1",
      "\n\e[90m(Use #{left_right} arrow keys, press Enter to select)\e[0m",
      "\e[2K\e[1G\e[1A\e[2K\e[1G",
      "What size? ",
      symbols[:line] * 2,
      "\e[32m#{symbols[:bullet]}\e[0m",
      symbols[:line] * 8 + " 2",
      "\n\e[90m(Use #{left_right} arrow keys, press Enter to select)\e[0m",
      "\e[2K\e[1G\e[1A\e[2K\e[1G",
      "What size? \e[32m2\e[0m\n\e[?25h"
    ].join

    expect(prompt.output.string).to eq(expected_output)
  end

  it "changes to never show help" do
    prompt.on(:keypress) do |event|
      prompt.trigger(:keyright) if event.value == "l"
    end
    prompt.input << "l" << "l" << "\r"
    prompt.input.rewind

    res = prompt.slider("What size?", min: 0, max: 10, step: 1) do |range|
                          range.default 0
                          range.show_help :never
                        end
    expect(res).to eq(2)

    expected_output = [
      "\e[?25lWhat size? ",
      "\e[32m#{symbols[:bullet]}\e[0m",
      symbols[:line] * 10 + " 0",
      "\e[2K\e[1G",
      "What size? ",
      symbols[:line] * 1,
      "\e[32m#{symbols[:bullet]}\e[0m",
      symbols[:line] * 9 + " 1",
      "\e[2K\e[1G",
      "What size? ",
      symbols[:line] * 2,
      "\e[32m#{symbols[:bullet]}\e[0m",
      symbols[:line] * 8 + " 2",
      "\e[2K\e[1G",
      "What size? \e[32m2\e[0m\n\e[?25h"
    ].join

    expect(prompt.output.string).to eq(expected_output)
  end

  it "specifies values instead of calculated range" do
    prompt.on(:keypress) do |event|
      prompt.trigger(:keyright) if event.value == "l"
    end
    prompt.input << "l" << "l" << "\r"
    prompt.input.rewind

    res = prompt.slider("What letter?", values: %w[ a b c d e f g ]) do |range|
                          range.default 'b'
                        end
    expect(res).to eq('d')

    expected_output = [
      "\e[?25lWhat letter? ",
      symbols[:line] * 1,
      "\e[32m#{symbols[:bullet]}\e[0m",
      symbols[:line] * 5 + " b",
      "\n\e[90m(Use ←/→ arrow keys, press Enter to select)\e[0m\e[2K\e[1G",
      "\e[1A\e[2K\e[1G",
      "What letter? ",
      symbols[:line] * 2,
      "\e[32m#{symbols[:bullet]}\e[0m",
      symbols[:line] * 4 + " c",
      "\e[2K\e[1G",
      "What letter? ",
      symbols[:line] * 3,
      "\e[32m#{symbols[:bullet]}\e[0m",
      symbols[:line] * 3 + " d",
      "\e[2K\e[1G",
      "What letter? \e[32md\e[0m\n\e[?25h"
    ].join

    expect(prompt.output.string).to eq(expected_output)
  end

  it "specifies values through DSL" do
    prompt.on(:keypress) do |event|
      prompt.trigger(:keyleft) if event.value == "l"
    end
    prompt.input << "l" << "l" << "\r"
    prompt.input.rewind

    res = prompt.slider("What letter?") do |range|
                          range.default 'c'
                          range.values %w[ a b c d e f g ]
                        end
    expect(res).to eq('a')

    expected_output = [
      "\e[?25lWhat letter? ",
      symbols[:line] * 2,
      "\e[32m#{symbols[:bullet]}\e[0m",
      symbols[:line] * 4 + " c",
      "\n\e[90m(Use ←/→ arrow keys, press Enter to select)\e[0m\e[2K\e[1G",
      "\e[1A\e[2K\e[1G",
      "What letter? ",
      symbols[:line] * 1,
      "\e[32m#{symbols[:bullet]}\e[0m",
      symbols[:line] * 5 + " b",
      "\e[2K\e[1G",
      "What letter? ",
      "\e[32m#{symbols[:bullet]}\e[0m",
      symbols[:line] * 6 + " a",
      "\e[2K\e[1G",
      "What letter? \e[32ma\e[0m\n\e[?25h"
    ].join

    expect(prompt.output.string).to eq(expected_output)
  end
end
