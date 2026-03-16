# frozen_string_literal: true

ENV['RACK_ENV'] = 'test'

$LOAD_PATH.unshift File.expand_path('../../lib', __dir__)

require 'dotenv/load'
require 'minitest/autorun'
require 'minitest/pride'
require 'tuple_space'
