require 'socket'

require 'vncrec/rfb/encraw.rb'
require 'vncrec/rfb/enczrle.rb'
require 'vncrec/rfb/enchex.rb'

module VNCRec
  module RFB
    class Proxy
      attr_accessor :name, :w, :h, :io, :data

      # @param io [IO, #read, #sysread, #syswrite, #read_nonblock] string stream from VNC server.
      # @param rfbv [String] version of RFB protocol, 3.8 is the only supported by now
      # @param enc [Integer] encoding of video data used to transfer. One of the following:
      #  * {ENC_RAW}
      #  * {ENC_HEXTILE}
      #  * {ENC_ZRLE}
      # @param pf [Hash] pixel format:
      #  * {VNCRec::PIX_FMT_BGR8} - 8 bits per pixel
      #  * {VNCRec::PIX_FMT_BGR32} - 32 bits per pixel
      # @param auth [Array]:
      # * Constant class e.g. VNCRec::Authentication::VncAuthentication
      # * optional argument, e.g. password string
      def initialize(io, rfbv, enc, pf, auth)
        @io = io
        @version = rfbv
        @enc = enc
        @pf = pf
        @auth = auth.first.new(@io, *auth.drop(1))
      end

      # @param w width of the screen area
      # @param h height of the screen area
      # @param bpp bits per pixel
      def prepare_framebuffer(w, h, bpp)
        @w = w
        @h = h
        @bpp = bpp
        @bypp = (bpp / 8.0).to_i
        @wb = @w * @bypp
        @data = "\x00" * @wb * @h
      end

      # Perform handshake
      # @return w,h,server_name or nil
      def handshake
        # version
        version = @io.readpartial 12
        @io.syswrite(@version + "\n")

        @auth.handshake

        # client init
        @io.syswrite "\x01"

        # server init
        w = @io.readpartial(2).unpack('S>')[0]
        h = @io.readpartial(2).unpack('S>')[0]
        pf = @io.readpartial 16
        nlen = @io.readpartial(4).unpack('L>')[0]
        @name = @io.readpartial nlen
        return [w, h, @name]
      end

      # Set a way that server should use to represent pixel data
      # @param [Hash] pixel format:
      #  * {VNCRec::PIX_FMT_BGR8}
      #  * {VNCRec::PIX_FMT_BGRA}
      def set_pixel_format(format)
        msg = [0, 0, 0, 0].pack('CC3')
        begin
          @io.syswrite msg

          msg = [
            format[:bpp],
            format[:depth],
            format[:bend],
            format[:tcol],
            format[:rmax],
            format[:gmax],
            format[:bmax],
            format[:rshif],
            format[:gshif],
            format[:bshif],
            0, 0, 0
          ].pack('CCCCS>S>S>CCCC3')
          return @io.syswrite msg

        rescue
          return nil
        end
      end

      # Set way of encoding video frames.
      # @param encodings [Array<Integer>] encoding of video data used to transfer.
      #  * {ENC_RAW}
      #  * {ENC_HEXTILE}
      #  * {ENC_ZRLE}
      def set_encodings(encodings)
        num = encodings.size
        msg = [2, 0, num].pack('CCS>')
        begin
          @io.syswrite msg
          encodings.each do |e|
            @io.syswrite([e].pack('l>'))
          end
        rescue
          return nil
        end
      end

      # Request framebuffer update.
      # @param [Integer] inc incremental, request just difference
      #  between previous and current framebuffer state.
      # @param x [Integer]
      # @param y [Integer]
      # @param w [Integer]
      # @param h [Integer]
      def fb_update_request(inc, x, y, w, h)
        @inc = inc > 0
        msg = [3, inc, x, y, w, h].pack('CCS>S>S>S>')
        return @io.write msg
      rescue
        return nil
      end

      # Handle VNC server response. Call it right after +fb_update_request+.
      # @return [Array] type, (either framebuffer, "bell", +handle_server_cuttext+ or +handle_colormap_update+ results)
      def handle_response
        t = (io.readpartial 1).ord
        case t
        when 0 then
          handle_fb_update
          return [t, @data]
        when 1 then
          return [t, handle_colormap_update]
        when 2 then
          return [t, 'bell']
        when 3 then
          return [t, handle_server_cuttext]
        else
          return [-1, nil]
        end
      end

      # Receives data and applies diffs(if incremental) to the @data
      def handle_fb_update
        fail 'run #prepare_framebuffer first' unless @data
        enc = nil
        @encs ||= { 0 => VNCRec::RFB::EncRaw,
                    5 => VNCRec::RFB::EncHextile,
                    16 => VNCRec::RFB::EncZRLE
        }
        _, numofrect = @io.read(3).unpack('CS>')
        i = 0
        while i < numofrect
          hdr = @io.read 12
          x, y, w, h, enc = hdr.unpack('S>S>S>S>l>')
          mod = @encs.fetch(enc) { fail "Unsupported encoding #{enc}" }
          mod.read_rect @io, x, y, w, h, @bpp, @data, @wb, @h
          i += 1
        end
      end

      # @return [Array] palette
      def handle_colormap_update
        _, first_color, noc = (@io.read 5).unpack('CS>S>')
        palette = []
        noc.times do
          palette << (@io.read 6).unpack('S>S>S>')
        end
        return palette
      rescue
        return nil
      end

      # @return [String] server cut text
      def handle_server_cuttext
        begin
          _, _, _, len = (@io.read 7).unpack('C3L>')
          text = @io.read len
        rescue
          return nil
        end
        text
      end
    end
  end
end
