# frozen_string_literal: true

# Branded HTML email templates for Rodauth transactional emails
module EmailTemplates
  COLORS = {button_bg: '#211d21', button_hover: '#312c31', body_text: '#575057', light_text: '#857a86', border: '#d6d0d6', background: '#fbfafb'}.freeze

  module_function

  def verify_account_body link
    wrap_email(
      heading: 'Verify your email',
      body_text: 'Thanks for signing up! Click below to verify your email and start finding free books at your library.',
      button_text: 'Verify My Email',
      button_url: link
    )
  end

  def reset_password_body link
    wrap_email(
      heading: 'Reset your password',
      body_text: "Click below to reset your Yonderbook password. If you didn't request this, you can safely ignore this email.",
      button_text: 'Reset Password',
      button_url: link
    )
  end

  def email_auth_body link
    wrap_email(
      heading: 'Your login link',
      body_text: 'Click below to log in to your Yonderbook account. This link expires in 24 hours.',
      button_text: 'Log In to Yonderbook',
      button_url: link
    )
  end

  def wrap_email heading:, body_text:, button_text:, button_url:
    <<~HTML
      <!DOCTYPE html>
      <html>
      <head><meta charset="utf-8"></head>
      <body style="margin:0;padding:0;background-color:#{COLORS[:background]};font-family:system-ui,sans-serif;">
        <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background-color:#{COLORS[:background]};">
          <tr><td align="center" style="padding:40px 20px;">
            <table role="presentation" width="600" cellpadding="0" cellspacing="0" style="max-width:600px;width:100%;">
              <tr><td align="center" style="padding-bottom:32px;">
                <span style="font-family:system-ui,sans-serif;font-size:24px;font-weight:600;color:#{COLORS[:button_bg]};">Yonderbook</span>
              </td></tr>
              <tr><td style="background-color:#ffffff;border:1px solid #{COLORS[:border]};border-radius:8px;padding:40px 32px;">
                <h1 style="margin:0 0 16px;font-family:system-ui,sans-serif;font-size:22px;font-weight:600;color:#{COLORS[:button_bg]};">#{heading}</h1>
                <p style="margin:0 0 28px;font-family:system-ui,sans-serif;font-size:16px;line-height:24px;color:#{COLORS[:body_text]};">#{body_text}</p>
                <table role="presentation" cellpadding="0" cellspacing="0"><tr><td align="center" style="border-radius:9999px;background-color:#{COLORS[:button_bg]};">
                  <a href="#{button_url}" style="display:inline-block;padding:14px 28px;font-family:system-ui,sans-serif;font-size:16px;font-weight:500;color:#ffffff;text-decoration:none;border-radius:9999px;">#{button_text}</a>
                </td></tr></table>
                <p style="margin:24px 0 0;font-family:system-ui,sans-serif;font-size:12px;line-height:18px;color:#{COLORS[:light_text]};word-break:break-all;">#{button_url}</p>
              </td></tr>
              <tr><td align="center" style="padding-top:24px;">
                <p style="margin:0;font-family:system-ui,sans-serif;font-size:12px;color:#{COLORS[:light_text]};">You're receiving this because you signed up at yonderbook.com.</p>
              </td></tr>
            </table>
          </td></tr>
        </table>
      </body>
      </html>
    HTML
  end
end
