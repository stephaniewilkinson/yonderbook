# frozen_string_literal: true

require 'mail'
require 'roda'

# Configure Mail delivery globally
rack_env = ENV['RACK_ENV'] || 'development'

if %w[development test].include?(rack_env)
  # Development/Test: use test delivery method
  Mail.defaults do
    delivery_method :test
  end
else
  # Production: Mailgun SMTP (5,000 emails/month free)
  Mail.defaults do
    delivery_method :smtp,
                    {
                      address: 'smtp.mailgun.org',
                      port: 587,
                      user_name: ENV.fetch('MAILGUN_SMTP_LOGIN', nil),
                      password: ENV.fetch('MAILGUN_SMTP_PASSWORD', nil),
                      authentication: 'plain',
                      enable_starttls_auto: true
                    }
  end
end

class Mailer < Roda
  plugin :render
  plugin :mailer

  # Helper method to get default from address
  def default_from
    ENV['FROM_EMAIL'] || 'noreply@yonderbook.com'
  end

  route do |r|
    # Test emails - /test
    r.mail 'test' do
      from default_from
      to 'test@example.com'
      subject 'Test Email'
      'This is a test email from Yonderbook.'
    end
  end
end

# Convenience service class for easier usage
class EmailService
  class << self
    def send_test_email _to: nil, _subject: nil, _body: nil
      # Currently uses fixed route, but keeps interface for future enhancement
      mail = Mailer.sendmail('/test')
      log_in_development(mail)
      mail
    rescue StandardError => e
      puts "Email delivery error: #{e.message}" if ENV['RACK_ENV'] == 'development'
      raise e
    end

    def send_notification_email _to:, _subject:, _body:
      # For now, use test email until we implement a proper notification route
      # TODO: Implement dynamic notification route using to:, subject:, body: parameters
      mail = Mailer.sendmail('/test')
      log_in_development(mail)
      mail
    rescue StandardError => e
      puts "Email delivery error: #{e.message}" if ENV['RACK_ENV'] == 'development'
      raise e
    end

    private

    def log_in_development mail
      return unless ENV['RACK_ENV'] == 'development'

      puts "\n=== EMAIL SENT (Development Mode) ==="
      puts "From: #{mail.from}"
      puts "To: #{mail.to}"
      puts "Subject: #{mail.subject}"
      puts "Body: #{mail.body}"
      puts "====================================\n"
    end
  end
end
