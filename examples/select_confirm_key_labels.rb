# frozen_string_literal: true

require_relative "../lib/tty-prompt"

prompt = TTY::Prompt.new

warriors = %w[Scorpion Kano Jax Kitana Raiden]

answer = prompt.select("Choose your destiny?", warriors,
                       confirm_keys: [:enter, {escape: "ESC"}, ","])

puts answer.inspect