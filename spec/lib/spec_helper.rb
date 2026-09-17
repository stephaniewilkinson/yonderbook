# frozen_string_literal: true

ENV['RACK_ENV'] = 'test'

$LOAD_PATH.unshift File.expand_path('../../lib', __dir__)

require 'dotenv/load'
require 'minitest/autorun'
require 'minitest/pride'
require 'tuple_space'
# Blocks the network and provides the fixtures. An unstubbed call raises
# WebMock::NetConnectNotAllowedError naming the request, rather than silently
# depending on Goodreads, OverDrive, BookMooch or OpenLibrary being up.
require_relative '../support/http_mocking'
