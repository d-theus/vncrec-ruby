require "vncrec/constants.rb"
require "timeout"
require "thread"

module VNCRec
  # Writers are wrappers for video files.
  module Writers
    # Raw video writer. Very similar to File
    class RawVideo
      def initialize(filename)
        @filename = filename
        @file = File.open(filename, 'w')
      end

      def write(data)
        @file.write data
        @file.flush
      end

      def close
        @file.close
      end

      def closed?
        @file.closed?
      end

      def size
        @file.size
      end
    end

    # FFmpeg writer. Pipes video to FFmpeg instance exactly
    # *fps* times per second. Audio addition is also
    # supported (`:ffmpeg_ia`- and `:ffmpeg_out_opts strings`)
    class FFmpeg
      # @param filename [String] a name for video file.
      #  Should contain extension i.e. _.mp4_ of _.flv_.
      # @note Choose _-acodec_ option in +:ffmpeg_out_opts+ accordingly.
      # @param opts [Hash] options:
      #  * fps
      #  * pix_fmt (see +:colormode+)
      #  * geometry
      #  * ffmpeg_iv_opts
      #  * ffmpeg_ia_opts
      #  * ffmpeg_out_opts
      #  See {VNCRec::Recorder#initialize} for descriptions
      def initialize(filename, opts = {})
        @filename = filename
        @fps = opts[:fps] || 12
        pf = opts.fetch(:pix_fmt) { fail 'Undefined pixel format' }
        @pix_fmt = get_pix_fmt pf
        @size = opts.fetch(:geometry) { fail 'Undefined frame size' }
        @frame_length = frame_length
        @ffmpeg_iv_opts = opts[:ffmpeg_iv_opts]
        @ffmpeg_ia_opts = opts[:ffmpeg_ia_opts]
        @ffmpeg_out_opts = opts[:ffmpeg_out_opts]
        @cmd = "ffmpeg -y -s #{@size} -r #{@fps} -f rawvideo -pix_fmt #{@pix_fmt[:string]} \
        #{@ffmpeg_iv_opts} \
      -i pipe:0 \
        #{@ffmpeg_ia_opts} \
        #{@ffmpeg_out_opts} #{@filename} &>/dev/null"
        @data_avail = false
        spawn
      end

      def write(data)
        begin
          written = @pipe_to_writer.syswrite(data)
        rescue Errno::EPIPE
          raise 'No writer running'
        end
        fail 'Not enough data is piped to writer' if written % @frame_length != 0
        @pipe_to_writer.flush
        @data_avail = true
      end

      def close
        Process.kill('KILL', @pid)
        Timeout.timeout(5) do
          Process.waitpid(@pid)
        end
      rescue Timeout::Error
        raise 'Writer hanged'
      rescue Errno::ESRCH, Errno::ECHILD
        raise 'No writer running'
      end

      def closed?
        Timeout.timeout(0.05) do
          Process.waitpid(@pid)
          return true
        end
      rescue Timeout::Error
        return false
      rescue Errno::ECHILD
        return true
      end

      # @return [Integer] filesize. If no file created yet
      #  0 is returned.
      def size
        s = File.size(@filename)
        return s
      rescue Errno::ENOENT
        return 0
      end

      private

      def spawn
        @pipe, @pipe_to_writer = IO.pipe
        @pid = fork do
          Signal.trap('INT') {}
          @pipe_to_writer.close
          @lock = Mutex.new
          @written = 0
          @output_ready = false
          STDIN.reopen(@pipe)
          routine
        end
        @pipe.close
      end

      def routine
        @output = IO.popen(@cmd)
        @output_ready = true
        IO.select([STDIN])
        @th = Thread.new(thread_func)
        loop do
          data = STDIN.read(@frame_length)
          fail 'wrong length' if data.length != @frame_length
          if @lock.try_lock
            @framebuffer = data
            @lock.unlock
          else
            @framebuffer2 = data
            @cached = true
          end
        end
      end

      def flush
        return unless @output.closed? || @data_avail
        @lock.synchronize do
          if @cached
            @framebuffer = @framebuffer2
            @cached = false
          end
          @written += @output.syswrite @framebuffer
          @output.flush
        end
      end

      def thread_func
        adjust_sleep_time { flush }
        i = 0
        loop do
          i += 1
          if (i % 100) == 0
            adjust_sleep_time { flush }
          else
            flush
          end
          sleep @sl
        end
      end

      def frame_length
        bpp = @pix_fmt[:bpp] / 8
        dim = @size.split('x').map(&:to_i).reduce(&:*)
        bpp * dim
      end

      def adjust_sleep_time(&_block)
        t1 = Time.now
        yield
        t2 = Time.now
        @sl = 1.0 / @fps - (t2 - t1)
      end

      def get_pix_fmt(fmt)
        sym = fmt.to_s.upcase.prepend('PIX_FMT_').to_sym
        fail "Unknown pixel format #{fmt}" unless VNCRec.const_defined? sym
        VNCRec.const_get(sym)
      end
    end

    def self.get_writer(filename, opts = {})
      begin
        File.write(filename, '')
      rescue Errno::EACCES
        raise 'Cannot create output file'
      end
      @path, @filename = File.split filename
      @extname = File.extname filename
      return RawVideo.new(@path + '/' + @filename) if @extname == '.raw'
      if @extname.empty?
        if @path != '/dev'
          return RawVideo.new(@path + '/' + @filename + '.raw')
        else
          return FFmpeg.new(@path + '/' + @filename, opts)
        end
      else
        return FFmpeg.new(@path + '/' + @filename, opts)
      end
    end
  end
end
