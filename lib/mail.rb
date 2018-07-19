# frozen_string_literal: true

require 'sendgrid-ruby'
require 'dotenv/load'

module Mail
  include SendGrid

  module_function

  @email_template = File.read('views/email.html')

  def send_welcome_email(user_email)
    # TODO: set this email address up
    from = Email.new(email: 'welcome@yonderbook.com')
    to = Email.new(email: user_email)
    subject = "You've signed up for Yonderbook"
    content = Content.new(type: 'text/html', value: @email_template)
    mail = Mail.new(from, subject, to, content)
    sg = SendGrid::API.new(api_key: ENV['SENDGRID_API_KEY'])
    sg.client.mail._('send').post(request_body: mail.to_json)
  end
end
