# MailChannels Email API Ruby client

Published on RubyGems as [`mailchannels-email-api`](https://rubygems.org/gems/mailchannels-email-api).
This repository is the public development source.
Support: dev@mailchannels.com. Report reproducible bugs through this repository’s issues.

This Ruby 3.2+ client calls the current MailChannels Email API directly with an
API key. It accepts the API's full send payload, including personalizations,
plain text or HTML content, attachments, and custom headers. It does not need a
Cloudflare Worker. It is a sending client, not an Action Mailer delivery backend.

## Try a validation request

Install the gem:

```sh
gem install mailchannels-email-api
```

Provide `MAILCHANNELS_API_KEY` through your environment or secret store. Configure
your sender domain and use an allowed recipient. The free plan permits 100
emails/day and restricts recipients to verified account users until a payment
method is added.

```ruby
require 'mailchannels/email_api'

client = MailChannels::EmailAPI::Client.new
message = {
  from: { email: ENV.fetch('MAILCHANNELS_SENDER') },
  personalizations: [
    { to: [{ email: ENV.fetch('MAILCHANNELS_RECIPIENT') }] }
  ],
  subject: 'MailChannels Ruby validation',
  content: [{ type: 'text/plain', value: 'Validate this message without sending.' }]
}

result = client.validate_email(message)
puts result.validated? # HTTP 200, no email sent
```

To send deliberately, call `client.send_email(message)`. An HTTP 202 result has
`accepted? == true`; it means accepted for processing, not delivered. A dry run
is HTTP 200 and never reports acceptance. Unexpected statuses, including
redirects, raise `MailChannels::EmailAPI::APIError` with a `status` attribute.

Payloads use the [API's JSON schema](https://docs.mailchannels.com/email-api.yaml)
without shorthand conversion. Both string and symbol Hash keys serialize to
JSON keys. See the [API documentation](https://docs.mailchannels.com/email-api/overview)
for attachment encoding and other supported fields.

## Failure handling and lifecycle

The client opens and closes an HTTPS session per call. TLS peer verification is
enabled. Connect timeout is 10 seconds; read and write timeouts are 30 seconds
each. These are I/O timeouts, not a total request deadline. It does not follow
redirects, use environment proxies, or automatically retry requests.

An ambiguous transport failure can occur after the server accepts a message.
Check delivery records before retrying. `TransportError` has a sanitized message
and does not retain the underlying exception as its cause. API error messages
contain the HTTP status rather than response bodies. Client inspection redacts
the API key; application code should also avoid logging requests or payloads.

Ruby argument/JSON serialization errors propagate to the caller before network
I/O. Use a separate client for each account's key. In Rails, call this client
from your application service or job; it does not change `ActionMailer` settings.

## Test and package

```sh
bundle install
bundle exec ruby -Ilib -e 'Dir["test/*_test.rb"].sort.each { |file| require_relative file }'
gem build mailchannels-email-api.gemspec
```

Unit tests replace the HTTP session; six native transport tests use a local TLS server with
synthetic credentials and messages. They exercise the real Net::HTTP transport, preserve API
hostname verification, and route only the expected API socket to loopback. Native tests cover
empty 202, dry-run 200, untrusted CA, hostname mismatch, redirects, HTTP errors and disconnect after
receipt. No real API request or email is sent. These checks do not replace separately authorized provider validation. See [RELEASING.md](RELEASING.md) for the release gates.
Bundler may compile the `json` dependency; development containers need a C
compiler and make (for example, Debian's `build-essential` package).
