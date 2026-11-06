# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name = 'mailchannels-email-api'
  spec.version = '0.1.0'
  spec.authors = ['MailChannels Corporation']
  spec.email = ['dev@mailchannels.com']
  spec.summary = 'A Ruby library for MailChannels Email API: send transactional email from your Ruby app.'
  spec.description = 'Send transactional email, such as sign-up confirmations, password resets, receipts and notifications, from your Ruby app through the MailChannels Email API. A direct HTTPS client with API-key authentication, dry-run validation, explicit acceptance status, bounded I/O timeouts and no automatic retries.'
  spec.license = 'MIT'
  spec.required_ruby_version = '>= 3.2'
  spec.homepage = 'https://www.mailchannels.com/email-api/'
  spec.metadata = {
    'source_code_uri' => 'https://github.com/mailchannels/mailchannels-email-api-ruby',
    'bug_tracker_uri' => 'https://github.com/mailchannels/mailchannels-email-api-ruby/issues',
    'documentation_uri' => 'https://docs.mailchannels.com/email-api/overview',
    'allowed_push_host' => 'https://rubygems.org',
    'rubygems_mfa_required' => 'true'
  }
  spec.files = Dir['lib/**/*.rb'] + ['README.md', 'LICENSE']
  spec.require_paths = ['lib']
  spec.add_dependency 'json', '>= 2.6', '< 3'
  spec.add_dependency 'net-http', '>= 0.4', '< 1'
end
