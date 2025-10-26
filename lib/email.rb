# frozen_string_literal: true

require 'resend'

# Email service using Resend for transactional emails
class EmailService
  class << self
    def send_email to:, subject:, html:, text: nil
      # Only use console output in test environment, send real emails in development
      return console_output(to, subject, html) if test_environment?

      # Set API key globally for Resend
      Resend.api_key = ENV.fetch('RESEND_API_KEY')

      params = {from: from_email, to: [to], subject: subject, html: html}
      params[:text] = text if text

      Resend::Emails.send(params)
    rescue StandardError => e
      puts "Email delivery error: #{e.message}"
      puts "Email params: #{params.inspect}"
      raise e
    end

    private

    def from_email
      'app@yonderbook.com'
    end

    def test_environment?
      ENV.fetch('RACK_ENV', nil) == 'test'
    end

    def console_output recipient, email_subject, email_html
      puts "\n=== EMAIL (Development Mode) ==="
      puts "From: #{from_email}"
      puts "To: #{recipient}"
      puts "Subject: #{email_subject}"
      puts "Body: #{email_html}"
      puts "==================================\n"
    end
  end
end
