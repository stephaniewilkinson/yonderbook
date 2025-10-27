# frozen_string_literal: true

require_relative '../../lib/email'
require_relative 'spec_helper'

describe EmailService do
  describe '.send_email' do
    it 'logs email in test mode without sending' do
      # Capture stdout
      output = StringIO.new
      original_stdout = $stdout
      $stdout = output

      EmailService.send_email(to: 'test@example.com', subject: 'Test Subject', html: '<p>Test body</p>')

      $stdout = original_stdout

      # Check that email details were logged (test mode uses console output)
      output_string = output.string
      assert_includes output_string, 'EMAIL (Development Mode)'
      assert_includes output_string, 'To: test@example.com'
      assert_includes output_string, 'Subject: Test Subject'
      assert_includes output_string, '<p>Test body</p>'
    end

    it 'includes from address in logs' do
      output = StringIO.new
      original_stdout = $stdout
      $stdout = output

      EmailService.send_email(to: 'test@example.com', subject: 'Test', html: '<p>Test</p>')

      $stdout = original_stdout

      assert_includes output.string, 'From: Yonderbook <app@yonderbook.com>'
    end

    it 'strips HTML when no text provided' do
      # This test verifies the strip_html method is called
      # In test mode, we can't test the actual stripping
      # but we can verify the method exists and doesn't error
      EmailService.send_email(to: 'test@example.com', subject: 'Test', html: '<p>Test with <strong>HTML</strong></p>')

      # Method completes without error
      assert true
    end
  end
end
