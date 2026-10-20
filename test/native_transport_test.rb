# frozen_string_literal: true

require 'minitest/autorun'
require 'minitest/mock'
require 'socket'
require 'tmpdir'
require 'mailchannels/email_api'

# Only connection routing and fixture CA trust change. The client's real Net::HTTP,
# TLS verification, serialization, status handling and timeout settings run unchanged.
class NativeTransportTest < Minitest::Test
  API = MailChannels::EmailAPI

  def setup
    @requests = []
    @threads = []
    @sockets = []
    @status = 202
    @mode = :response
    @tmp = Dir.mktmpdir
    @original_new = Net::HTTP.method(:new)
    start_server('api.mailchannels.net')
  end

  def start_server(hostname)
    key = OpenSSL::PKey::RSA.new(2048)
    cert = OpenSSL::X509::Certificate.new
    cert.version = 2
    cert.serial = 1
    cert.subject = cert.issuer = OpenSSL::X509::Name.parse("/CN=#{hostname}")
    cert.public_key = key.public_key
    cert.not_before = Time.now - 60
    cert.not_after = Time.now + 3600
    factory = OpenSSL::X509::ExtensionFactory.new
    factory.subject_certificate = factory.issuer_certificate = cert
    cert.add_extension(factory.create_extension('basicConstraints', 'CA:TRUE', true))
    cert.add_extension(factory.create_extension('subjectAltName', "DNS:#{hostname}"))
    cert.sign(key, OpenSSL::Digest::SHA256.new)
    @ca = File.join(@tmp, 'fixture-ca.pem')
    File.write(@ca, cert.to_pem)
    context = OpenSSL::SSL::SSLContext.new
    context.cert = cert
    context.key = key
    @tcp = TCPServer.new('127.0.0.1', 0)
    @port = @tcp.addr[1]
    @server = OpenSSL::SSL::SSLServer.new(@tcp, context)
    @acceptor = Thread.new do
      loop do
        begin
          socket = @server.accept
          @sockets << socket
          @threads << Thread.new(socket) { |connection| handle(connection) }
        rescue OpenSSL::SSL::SSLError
          # Expected for the untrusted-CA and hostname-mismatch tests.
          next
        end
      end
    rescue IOError, Errno::EBADF
      nil
    end
  end

  def handle(socket)
    request_line = socket.gets("\r\n")
    return unless request_line

    headers = {}
    while (line = socket.gets("\r\n")) && line != "\r\n"
      key, value = line.split(':', 2)
      headers[key.downcase] = value.strip
    end
    body = socket.read(Integer(headers.fetch('content-length')))
    @requests << {line: request_line.strip, headers: headers, body: JSON.parse(body)}
    return if @mode == :disconnect
    response = "HTTP/1.1 #{@status} Fixture\r\nContent-Length: 0\r\nConnection: close\r\n"
    response += "Location: https://untrusted.example.test/collect\r\n" if (300..399).cover?(@status)
    socket.write(response + "\r\n")
  rescue IOError, SystemCallError, OpenSSL::SSL::SSLError
    nil
  ensure
    socket.close
  end

  def stop_server
    @tcp.close unless @tcp.closed?
    @acceptor.kill.join
    @threads.each { |thread| thread.kill.join }
    @sockets.each { |socket| socket.close rescue nil }
  end

  def teardown
    stop_server
    FileUtils.remove_entry(@tmp)
  end

  def call(dry_run: false, trusted: true)
    route = lambda do |host, port, proxy|
      assert_equal ['api.mailchannels.net', 443, nil], [host, port, proxy]
      http = @original_new.call(host, @port, nil)
      http.ipaddr = '127.0.0.1'
      http.ca_file = @ca if trusted
      http
    end
    Net::HTTP.stub(:new, route) do
      API::Client.new(api_key: 'synthetic-fixture-key').send_email(
        {from: {email: 'sender@example.test'}, personalizations: [{to: [{email: 'team@example.test'}]}],
         content: [{type: 'text/plain', value: 'Synthetic TLS fixture'}]}, dry_run: dry_run
      )
    end
  end

  def test_verified_tls_empty_202_and_request_mapping
    result = call
    assert result.accepted?
    refute result.validated?
    assert_equal 1, @requests.size
    request = @requests.first
    assert_equal 'POST /tx/v1/send HTTP/1.1', request[:line]
    assert_equal 'synthetic-fixture-key', request[:headers]['x-api-key']
    assert_equal 'sender@example.test', request[:body]['from']['email']
  end

  def test_native_dry_run_is_validation_only
    @status = 200
    result = call(dry_run: true)
    assert result.validated?
    refute result.accepted?
    assert_equal 'POST /tx/v1/send?dry-run=true HTTP/1.1', @requests.first[:line]
  end

  def test_untrusted_ca_rejected_before_request
    error = assert_raises(API::TransportError) { call(trusted: false) }
    assert_nil error.cause
    assert_empty @requests
  end

  def test_hostname_mismatch_rejected_before_request
    stop_server
    @threads = []; @sockets = []
    start_server('wrong.example.test')
    assert_raises(API::TransportError) { call }
    assert_empty @requests
  end

  def test_redirects_not_followed
    [301, 302, 303, 307, 308].each do |status|
      @status = status
      before = @requests.size
      error = assert_raises(API::APIError) { call }
      assert_equal status, error.status
      assert_equal before + 1, @requests.size
    end
  end

  def test_api_errors_not_retried
    [400, 401, 429, 500, 503].each do |status|
      @status = status
      before = @requests.size
      error = assert_raises(API::APIError) { call }
      assert_equal status, error.status
      assert_equal before + 1, @requests.size
      refute_includes error.message, 'synthetic-fixture-key'
    end
  end

  def test_disconnect_after_receipt_does_not_retry
    @mode = :disconnect
    error = assert_raises(API::TransportError) { call }
    assert_nil error.cause
    assert_equal 1, @requests.size
  end
end
