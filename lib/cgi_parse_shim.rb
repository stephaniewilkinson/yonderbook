# frozen_string_literal: true

require 'cgi'
require 'uri'

# Ruby 4.0 removed CGI.parse; the oauth gem still calls it.
#
# OAuth::RequestProxy::Net::HTTP::HTTPRequest#all_parameters reaches for it
# while signing a request, so without this every OAuth call dies with a
# NoMethodError from inside the gem rather than anywhere in this codebase.
#
# This lives in its own file, required by lib/auth.rb rather than by app.rb,
# so that anything touching OAuth gets the shim -- including a spec that
# exercises Auth without booting the whole Roda app.
unless CGI.respond_to?(:parse)
  def CGI.parse query_string
    URI.decode_www_form(query_string).each_with_object({}) do |(k, v), hash|
      (hash[k] ||= []) << v
    end
  end
end
