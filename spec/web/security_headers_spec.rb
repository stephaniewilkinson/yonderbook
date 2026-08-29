# frozen_string_literal: true

require_relative 'spec_helper'

describe 'Security headers' do
  include Rack::Test::Methods

  let :app do
    App
  end

  # Rack 3 lowercases header names; older stacks do not. Look it up either way
  # so this spec is not testing the Rack version.
  def header name
    key = last_response.headers.keys.find { |candidate| candidate.downcase == name }
    last_response.headers[key]
  end

  def csp
    get '/'
    header 'content-security-policy'
  end

  describe 'content security policy' do
    it 'allows the analytics script to load' do
      assert_includes csp, 'https://cdn.usefathom.com'
    end

    # Universal Analytics stopped processing data on 1 July 2023. The tag is
    # gone; the policy should not still permit it.
    it 'no longer permits Google Analytics' do
      refute_includes csp, 'google-analytics'
    end

    it 'no longer permits Google Tag Manager' do
      refute_includes csp, 'googletagmanager'
    end

    it 'refuses to be framed' do
      assert_includes csp, "frame-ancestors 'none'"
    end

    it 'restricts form submissions to this site and Goodreads' do
      assert_includes csp, 'form-action'
    end
  end

  describe 'transport security' do
    it 'sends HSTS' do
      get '/'

      assert_includes header('strict-transport-security'), 'max-age=31536000'
    end
  end

  describe 'analytics gating' do
    # Production only, matching how the old GA tag was gated, so local and CI
    # traffic never pollutes the numbers.
    it 'does not load the analytics script outside production' do
      get '/'

      refute_includes last_response.body, 'usefathom'
    end
  end
end
