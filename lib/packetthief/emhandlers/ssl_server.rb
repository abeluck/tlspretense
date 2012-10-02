module PacketThief
  module EMHandlers

    # Basic SSL/TLS Server built on Ruby's OpenSSL objects instead of on
    # EventMachine's start_tls. This allows you to manipulate the SSLContext
    # and other details of the connection that EM normally doesn't let you
    # touch.
    #
    # Subclass it and override any of the methods in the following example to
    # use the the functionality.
    #
    # You can #send_data to send encrypted data to the other side, and
    # #receive_data will be called when there is data for the handler.
    #
    #   EM.run {
    #     SSLServer.start 'localhost', 54321 do |p|
    #
    #       # Note: this code block is actually too late to set up a new
    #       # #post_init since it runs just after post_init.
    #       def p.post_init
    #         # modify p.ctx to configure your certificates, key, etc.
    #       end
    #
    #       def servername_cb(sock, hostname)
    #         # implement your own SNI handling callback. The default will
    #         # return the originally configured context.
    #       end
    #
    #       def p.tls_successful_handshake
    #         # the handshake succeeded
    #       end
    #
    #       def p.tls_failed_handshake(e)
    #         # the ssl handshake failed, probably due to the client rejecting
    #         # your certificate. =)
    #       end
    #
    #       def p.unbind
    #         # unbind handler, called regardless of handshake success
    #       end
    #
    #       def p.receive_data(data)
    #         # do something with the unencrypted stream
    #         p.send_data("some message") # data to be encrypted then sent to the client
    #       end
    #
    #     end
    #   }
    #
    # Note: During #initialize and #post_init, this class
    # does not have access to its socket yet. Instead, use #tls_pre_start or
    # the code block you pass to .start to initialize the SSLContext, and use
    # #tls_post_accept to do anything once the SSL handshake has completed. You
    # can also override #servername_cb to perform the SNI callback.
    class SSLServer < AbstractSSLHandler

      def self.start(host, port, *args, &block)
        ssl_class = self

        serv = TCPServer.new host, port

        # We use InitialServer to listen for incoming connections. It will then
        # create the actual SSLServer.
        ::EM.watch serv, InitialServer, serv, ssl_class, args, block do |h|
          h.notify_readable = true
        end
      end

      ####

      # Handles the initial listening socket. We can't seem to use
      # EM.start_server -> EM.detach -> em.watch without triggering
      # (in EventMachine 1.0.0):
      #
      #   Assertion failed: (sd != INVALID_SOCKET), function _RunSelectOnce, file em.cpp, line 893.
      #
      # So we handle the server muckery ourselves.
      module InitialServer
        def initialize(servsocket, ssl_class, args, blk)
          @servsocket = servsocket
          @ssl_class = ssl_class
          @args = args
          @blk = blk
        end

        def notify_readable
          puts "InitialServer: Received a new connection, spawning a #{@ssl_class}"
          sock = @servsocket.accept_nonblock

          ::EM.watch sock, @ssl_class, sock, *@args do |h|
            h.notify_readable = true
            # Now call the caller's block.
            @blk.call(h)
            # And finally finish initialization by applying the context to an
            # SSLSocket, and setting the internal state.
            h.tls_begin
          end

        end

        def notify_writable
          puts "server socket notify writable"
        end
      end

      ####

      private
      # SSLServer uses accept_nonblock instead of connect_nonblock.
      def connection_action
        @sslsocket.accept_nonblock
      end

      ####

      public
      def initialize(tcpsocket)
        super(tcpsocket)
        @ctx.servername_cb = proc {|sslsocket, hostname| self.servername_cb(sslsocket, hostname) }
      end


      # Called when the client sends a hostname using the SNI TLS extension.
      #
      # This method should return an OpenSSL::SSL::SSLContext. It gives you an
      # opportunity to pick or generate a different server certificate or
      # certificate chain based on the hostname requested by the client.
      #
      # The default implementation does nothing by just returning the original
      # SSLContext.
      def servername_cb(sslsock, hostname)
        sslsock.context
      end

    end
  end
end
