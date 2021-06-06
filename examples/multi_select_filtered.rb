# frozen_string_literal: true

require_relative "../lib/tty-prompt"

prompt = TTY::Prompt.new

drinks = %w[vodka beer wine whisky bourbon]
prompt.multi_select("Choose your favourite drink?", drinks, filter: true)
