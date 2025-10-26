# frozen_string_literal: true

require 'resend'

# Email service using Resend for transactional emails
class EmailService
  class << self
    def send_email to:, subject:, html:, text: nil
      # Only use console output in test environment, send real emails in development
      return console_output(to, subject, html) if test_environment?

      begin
        # Set API key globally for Resend
        Resend.api_key = ENV.fetch('RESEND_API_KEY')

        # Generate plain text version if not provided (helps with spam filters)
        text ||= html_to_text(html)

        params = {from: from_email_with_name, to: [to], subject: subject, html: html, text: text}

        result = Resend::Emails.send(params)
        puts "✓ Email sent successfully to #{to}: #{subject}"
        puts "  Resend response: #{result.inspect}"
        result
      rescue StandardError => e
        puts "✗ Email delivery error: #{e.class} - #{e.message}"
        puts "  To: #{to}"
        puts "  Subject: #{subject}"
        puts "  Backtrace: #{e.backtrace.first(5).join("\n  ")}"
        raise e
      end
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
