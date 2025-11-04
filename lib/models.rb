# frozen_string_literal: true

# Load all Sequel model files from lib/models/
Dir[File.join(__dir__, 'models', '*.rb')].each { |file| require file }
