# frozen_string_literal: true

require 'json'
require 'net/http'
require 'openssl'

module MailChannels
  # Direct HTTPS access to the MailChannels Email API send endpoint.
  module EmailAPI
    VERSION = '0.1.0'

    class Error < StandardError; end
    class ConfigurationError < Error; end
    class TransportError < Error; end

    # HTTP errors deliberately omit response bodies and credentials.
    class APIError < Error
      attr_reader :status

      def initialize(status)
        @status = status
        super("MailChannels request failed (HTTP #{status})")
      end
    end

    # Acceptance is not delivery. A validation result never represents a send.
    class Result
      attr_reader :status

      def initialize(status, dry_run)
        @status = status
        @dry_run = dry_run
        freeze
      end

      def validated?
        @dry_run && status == 200
      end

      def accepted?
        !@dry_run && status == 202
      end
    end

    class Client
      HOST = 'api.mailchannels.net'
      PATH = '/tx/v1/send'

      # Credentials are copied so caller mutation cannot alter this client.
      def initialize(api_key: ENV['MAILCHANNELS_API_KEY'])
        unless api_key.is_a?(String) && !api_key.strip.empty? && !api_key.match?(/[\r\n]/)
          raise ConfigurationError, 'Set MAILCHANNELS_API_KEY or pass a nonempty api_key'
        end

        @api_key = api_key.dup.freeze
      end

      def inspect
        "#<#{self.class} api_key=[REDACTED]>"
      end
      alias to_s inspect

      # Accepts the API's full JSON payload: personalizations, content,
      # attachments, headers and other documented send fields pass through.
      # No redirects or retries are performed, including on ambiguous failures.
      def send_email(payload, dry_run: false)
        raise ArgumentError, 'payload must be a Hash' unless payload.is_a?(Hash)
        unless dry_run.equal?(true) || dry_run.equal?(false)
          raise ArgumentError, 'dry_run must be true or false'
        end

        request = Net::HTTP::Post.new(dry_run ? "#{PATH}?dry-run=true" : PATH)
        request['Content-Type'] = 'application/json'
        request['Accept'] = 'application/json'
        request['X-Api-Key'] = @api_key
        request['User-Agent'] = "mailchannels-email-api-ruby/#{VERSION}"
        request.body = JSON.generate(payload)

        http = Net::HTTP.new(HOST, 443, nil)
        http.use_ssl = true
        http.verify_mode = OpenSSL::SSL::VERIFY_PEER
        http.open_timeout = 10
        http.read_timeout = 30
        http.write_timeout = 30
        http.max_retries = 0
        response = http.start { |connection| connection.request(request) }
        status = response.code.to_i
        expected_status = dry_run ? 200 : 202
        raise APIError, status unless status == expected_status

        Result.new(status, dry_run)
      rescue Timeout::Error, SocketError, SystemCallError, IOError,
             OpenSSL::SSL::SSLError, Net::HTTPBadResponse, Net::ProtocolError
        raise TransportError,
              'MailChannels transport failed; delivery status may be unknown. No retry was attempted.',
              cause: nil
      end

      def validate_email(payload)
        send_email(payload, dry_run: true)
      end
    end
  end
end
