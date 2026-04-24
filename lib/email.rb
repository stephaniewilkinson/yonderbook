# frozen_string_literal: true

require 'resend'

# Email service using Resend for transactional emails
class EmailService
  FROM_EMAIL = 'Yonderbook <app@yonderbook.com>'

  class << self
    def send_email to:, subject:, html:, text: nil, tags: nil
      # Only use console output in test environment, send real emails in development
      return console_output(to, subject, html) if test_environment?

      begin
        # Set API key globally for Resend
        Resend.api_key = ENV.fetch('RESEND_API_KEY')

        params = {from: FROM_EMAIL, to: [to.strip], subject: subject, html: html}
        params[:text] = text if text
        params[:tags] = tags if tags

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

    def test_environment?
      ENV.fetch('RACK_ENV', nil) == 'test'
    end

    def console_output recipient, email_subject, _email_html
      puts "\n=== EMAIL (Test) → To: #{recipient} | Subject: #{email_subject} ===\n"
    end
  end
end
