module VNCRec
  module RFB
    module Authentication
      class Abstract
        def initialize(io, *args)
          @io = io
        end

        def to_msg
          [@code].pack('C')
        end

        def handshake
          types = get_security_types
          handle_types(types)
          send_type
          perform_authentication
          security_result
        end

        # Once the protocol version has been decided, the server and client
        # must agree on the type of security to be used on the connection.  The
        # server lists the security types that it supports:
        #
        # +--------------------------+-------------+--------------------------+
        # | No. of bytes             | Type        | Description              |
        # |                          | [Value]     |                          |
        # +--------------------------+-------------+--------------------------+
        # | 1                        | U8          | number-of-security-types |
        # | number-of-security-types | U8 array    | security-types           |
        # +--------------------------+-------------+--------------------------+
        # If the server listed at least one valid security type supported by
        # the client, the client sends back a single byte indicating which
        # security type is to be used on the connection:
        #
        #      +--------------+--------------+---------------+
        #      | No. of bytes | Type [Value] | Description   |
        #      +--------------+--------------+---------------+
        #      | 1            | U8           | security-type |
        #      +--------------+--------------+---------------+
        #
        # If number-of-security-types is zero, then for some reason the
        # connection failed (e.g., the server cannot support the desired
        # protocol version).  This is followed by a string describing the
        # reason (where a string is specified as a length followed by that many
        # ASCII characters):
        #
        #      +---------------+--------------+---------------+
        #      | No. of bytes  | Type [Value] | Description   |
        #      +---------------+--------------+---------------+
        #      | 4             | U32          | reason-length |
        #      | reason-length | U8 array     | reason-string |
        #      +---------------+--------------+---------------+
        #
        #  The server closes the connection after sending the reason-string.
        #  @return [Integer] types
        def get_security_types
          num_of_st = @io.readbyte
          if num_of_st == 0 # failed
            reason_len = @io.readpartial(4).unpack('L>')[0]
            reason = @io.readpartial(reason_len)
            raise reason
          else
            result = []
            num_of_st.times do
              result << @io.readbyte
            end
            result
          end
        end

        def handle_types(types)
          raise 'The server does not support requested auth method' unless types.include? @code
        end

        # If the server listed at least one valid security type supported by
        # the client, the client sends back a single byte indicating which
        # security type is to be used on the connection.
        def send_type
          @io.syswrite to_msg
        end

        # The server sends a word to inform the client whether the security
        # handshaking was successful.
        #
        #      +--------------+--------------+-------------+
        #      | No. of bytes | Type [Value] | Description |
        #      +--------------+--------------+-------------+
        #      | 4            | U32          | status:     |
        #      |              | 0            | OK          |
        #      |              | 1            | failed      |
        #      +--------------+--------------+-------------+
        #
        # If unsuccessful, the server sends a string describing the reason for
        # the failure, and then closes the connection:
        #
        #     +---------------+--------------+---------------+
        #     | No. of bytes  | Type [Value] | Description   |
        #     +---------------+--------------+---------------+
        #     | 4             | U32          | reason-length |
        #     | reason-length | U8 array     | reason-string |
        #     +---------------+--------------+---------------+
        #
        def security_result
          word = (@io.readpartial 4).unpack('L>').first
          if word != 0
            reason_len = (@io.readpartial 4).unpack('L>').first
            reason = @io.readpartial(reason_len)
            raise reason
          end
        end

        def perform_authentication
          raise 'NI'
        end
      end

      class None < Abstract
        def initialize(io, *args)
          super
          @code = 1
        end

        def perform_authentication
        end
      end

      class VncAuthentication < Abstract
        def initialize(io, *args)
          super
          @code = 2
          @password = args.first
        end

        # The server sends a random 16-byte challenge:
        #
        #      +--------------+--------------+-------------+
        #      | No. of bytes | Type [Value] | Description |
        #      +--------------+--------------+-------------+
        #      | 16           | U8           | challenge   |
        #      +--------------+--------------+-------------+
        #
        # The client encrypts the challenge with DES (ECB), using a password supplied
        # by the user as the key.  To form the key, the password is truncated
        # to eight characters, or padded with null bytes on the right.
        # Actually, each byte is also reversed. Challenge string is split
        # in two chunks of 8 bytes, which are encrypted separately and clashed together
        # again. The client then sends the resulting 16-byte response:
        #
        #      +--------------+--------------+-------------+
        #      | No. of bytes | Type [Value] | Description |
        #      +--------------+--------------+-------------+
        #      | 16           | U8           | response    |
        #      +--------------+--------------+-------------+
        #
        # The protocol continues with the SecurityResult message.
        def perform_authentication
          require 'openssl'

          challenge = @io.readpartial(16)
          split_challenge = [challenge.slice(0, 8), challenge.slice(8, 8)]

          cipher = OpenSSL::Cipher::DES.new(:ECB)
          cipher.encrypt
          cipher.key = normalized_password
          encrypted = split_challenge.reduce('') { |a, e| cipher.reset; a << cipher.update(e) }
          @io.syswrite encrypted
        end

        private

        def normalized_password
          rev = ->(n) { (0...8).reduce(0) { |a, e| a + 2**e * n[7 - e] } }
          inv = @password.each_byte.map { |b| rev[b].chr }.join
          inv.ljust(8, "\x00")
        end
      end
    end
  end
end
