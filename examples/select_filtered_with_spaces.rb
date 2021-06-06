# frozen_string_literal: true

require_relative "../lib/tty-prompt"

prompt = TTY::Prompt.new

warriors = ["Jax", "Jax Jr", "Kitana", "Raiden ft. Thunder"]

answer = prompt.select("Choose your destiny?", warriors,
                       filter: true, confirm_keys: %i[return ctrl_s])

puts answer.inspect
