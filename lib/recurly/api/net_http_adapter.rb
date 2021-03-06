require 'net/https'

module Recurly
  class API
    module Net
      module HTTPAdapter
        # A hash of Net::HTTP settings configured before the request.
        #
        # @return [Hash]
        def net_http
          @net_http ||= {}
        end

        # Used to store any Net::HTTP settings.
        #
        # @example
        #   Recurly::API.net_http = {
        #     :verify_mode => OpenSSL::SSL::VERIFY_PEER,
        #     :ca_path     => "/etc/ssl/certs",
        #     :ca_file     => "/opt/local/share/curl/curl-ca-bundle.crt"
        #   }
        attr_writer :net_http

        private

        METHODS = {
          :head   => ::Net::HTTP::Head,
          :get    => ::Net::HTTP::Get,
          :post   => ::Net::HTTP::Post,
          :put    => ::Net::HTTP::Put,
          :delete => ::Net::HTTP::Delete
        }

        def request method, uri, options = {}
          head = { 'Accept' => accept, 'User-Agent' => user_agent }
          accept_language and head['Accept-Language'] ||= accept_language
          head.update options[:head] if options[:head]
          uri = base_uri + uri
          if options[:params] && !options[:params].empty?
            uri += "?#{options[:params].map { |k, v| "#{k}=#{v}" }.join '&' }"
          end
          request = METHODS[method].new uri.request_uri, head
          request.basic_auth Recurly.api_key, nil
          if options[:body]
            head['Content-Type'] = content_type
            request.body = options[:body]
          end
          http = ::Net::HTTP.new uri.host, uri.port
          http.use_ssl = uri.scheme == 'https'
          net_http.each_pair { |key, value| http.send "#{key}=", value }

          if Recurly.logger
            Recurly.log :info, "===> %s %s" % [request.method, uri]
            headers = request.to_hash
            headers['authorization'] &&= ['Basic [FILTERED]']
            Recurly.log :debug, headers.inspect
            if request.body && !request.body.empty?
              Recurly.log :debug, XML.filter(request.body)
            end
            start_time = Time.now
          end

          response = http.start { http.request request }
          code = response.code.to_i

          if Recurly.logger
            latency = (Time.now - start_time) * 1_000
            level = case code
              when 200...300 then :info
              when 300...400 then :warn
              when 400...500 then :error
              else                :fatal
            end
            Recurly.log level, "<=== %d %s (%.1fms)" % [
              code,
              response.class.name[9, response.class.name.length].gsub(
                /([a-z])([A-Z])/, '\1 \2'
              ),
              latency
            ]
            Recurly.log :debug, response.to_hash.inspect
            Recurly.log :debug, response.body if response.body
          end

          case code
            when 200...300 then response
            else                raise ERRORS[code].new request, response
          end
        end
      end
    end

    extend Net::HTTPAdapter
  end
end
