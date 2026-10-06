# frozen_string_literal: true

require 'minitest/autorun'
require 'minitest/mock'
require 'mailchannels/email_api'

class ClientTest < Minitest::Test
  API = MailChannels::EmailAPI
  Response = Struct.new(:code)

  class Session
    attr_accessor :use_ssl, :verify_mode, :open_timeout, :read_timeout,
                  :write_timeout, :max_retries
    attr_reader :requests, :closed

    def initialize(status: '202', failure: nil)
      @status = status
      @failure = failure
      @requests = []
    end

    def start
      yield self
    ensure
      @closed = true
    end

    def request(request)
      @requests << request
      raise @failure if @failure

      Response.new(@status)
    end
  end

  def setup
    @client = API::Client.new(api_key: 'test-secret')
    @message = {
      from: { email: 'sender@example.com' },
      personalizations: [{ to: [{ email: 'recipient@example.net' }] }],
      subject: 'Unicode ✓',
      content: [{ type: 'text/plain', value: 'Hello' }],
      attachments: [{ filename: 'hello.txt', type: 'text/plain', content: 'SGVsbG8=' }],
      headers: { 'X-Application' => 'test' }
    }
  end

  def with_session(session)
    factory = lambda do |host, port, proxy|
      assert_equal 'api.mailchannels.net', host
      assert_equal 443, port
      assert_nil proxy
      session
    end
    Net::HTTP.stub(:new, factory) { yield session }
  end

  def test_send_preserves_payload_and_reports_acceptance
    original = Marshal.load(Marshal.dump(@message))
    with_session(Session.new) do |session|
      result = @client.send_email(@message)
      assert result.accepted?
      refute result.validated?
      assert_equal 202, result.status
      assert result.frozen?
      request = session.requests.fetch(0)
      assert_equal 'POST', request.method
      assert_equal '/tx/v1/send', request.path
      assert_equal JSON.parse(JSON.generate(original)), JSON.parse(request.body)
      assert_equal original, @message
      assert_equal 'test-secret', request['X-Api-Key']
      assert_equal 'application/json', request['Content-Type']
      assert_match(/mailchannels-email-api-ruby/, request['User-Agent'])
      assert session.closed
    end
  end

  def test_validate_never_reports_sent
    with_session(Session.new(status: '200')) do |session|
      result = @client.validate_email(@message)
      assert result.validated?
      refute result.accepted?
      assert_equal '/tx/v1/send?dry-run=true', session.requests.first.path
      assert_equal 1, session.requests.length
    end
  end

  def test_explicit_dry_run
    with_session(Session.new(status: '200')) do
      assert @client.send_email(@message, dry_run: true).validated?
    end
  end

  def test_tls_timeouts_and_retries
    with_session(Session.new) do |session|
      @client.send_email(@message)
      assert_equal true, session.use_ssl
      assert_equal OpenSSL::SSL::VERIFY_PEER, session.verify_mode
      assert_equal 10, session.open_timeout
      assert_equal 30, session.read_timeout
      assert_equal 30, session.write_timeout
      assert_equal 0, session.max_retries
    end
  end

  [301, 307, 400, 401, 403, 429, 500, 503].each do |status|
    define_method("test_http_#{status}_is_not_followed_or_retried") do
      with_session(Session.new(status: status.to_s)) do |session|
        error = assert_raises(API::APIError) { @client.send_email(@message) }
        assert_equal status, error.status
        assert_equal "MailChannels request failed (HTTP #{status})", error.message
        assert_equal 1, session.requests.length
        assert session.closed
      end
    end
  end

  def test_unexpected_success_is_not_misrepresented
    with_session(Session.new(status: '200')) do
      assert_raises(API::APIError) { @client.send_email(@message) }
    end
    with_session(Session.new(status: '202')) do
      assert_raises(API::APIError) { @client.validate_email(@message) }
    end
  end

  [Net::ReadTimeout, Net::OpenTimeout, Net::WriteTimeout, SocketError,
   Errno::ECONNRESET, OpenSSL::SSL::SSLError, EOFError,
   Net::HTTPBadResponse].each do |error_class|
    define_method("test_transport_error_#{error_class.name.gsub('::', '_')}") do
      with_session(Session.new(failure: error_class.new('test-secret'))) do |session|
        error = assert_raises(API::TransportError) { @client.send_email(@message) }
        refute_includes error.full_message, 'test-secret'
        assert_nil error.cause
        assert_match(/unknown/, error.message)
        assert_equal 1, session.requests.length
        assert session.closed
      end
    end
  end

  def test_invalid_configuration
    [nil, '', '   ', "key\r\nInjected: true", 123].each do |key|
      assert_raises(API::ConfigurationError) { API::Client.new(api_key: key) }
    end
  end

  def test_key_is_copied_and_inspection_redacts_it
    key = +'test-secret'
    client = API::Client.new(api_key: key)
    key.replace('changed')
    refute_includes client.inspect, 'test-secret'
    refute_includes client.to_s, 'test-secret'
    with_session(Session.new) do |session|
      client.send_email(@message)
      assert_equal 'test-secret', session.requests.first['X-Api-Key']
    end
  end

  def test_invalid_arguments_do_not_open_a_connection
    Net::HTTP.stub(:new, ->(*) { flunk 'Unexpected network access' }) do
      [nil, [], 'message'].each do |payload|
        assert_raises(ArgumentError) { @client.send_email(payload) }
      end
      ['false', 'true', nil, 0, 1].each do |flag|
        assert_raises(ArgumentError) { @client.send_email(@message, dry_run: flag) }
      end
      assert_raises(JSON::GeneratorError) { @client.send_email({ value: Float::NAN }) }
    end
  end

  def test_environment_key_is_supported
    old = ENV['MAILCHANNELS_API_KEY']
    ENV['MAILCHANNELS_API_KEY'] = 'from-environment'
    client = API::Client.new
    with_session(Session.new) do |session|
      client.send_email(@message)
      assert_equal 'from-environment', session.requests.first['X-Api-Key']
    end
  ensure
    ENV['MAILCHANNELS_API_KEY'] = old
  end
end
