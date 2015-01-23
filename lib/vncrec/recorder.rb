#!/usr/bin/env ruby
# encoding: utf-8
# @encoding "utf-8"

require 'socket'
require 'zlib'
require 'stringio'
require 'logger'
begin
  require 'logger/colors'
rescue LoadError
end

require 'vncrec/constants.rb'
require 'vncrec/rfb/proxy.rb'
require 'vncrec/writers.rb'

module VNCRec
  # A recorder itself.

  class Recorder
    DEFAULTS = {
      :pix_fmt      => :BGR8,
      :debug        => nil,
      :encoding     => VNCRec::ENC_RAW,
      :filename     => nil,
      :fps          => 6,
      :input        => nil,
      :port         => 5900
    }

    # @param geometry [String] geometry of the screen area to capture(+x,y offset is not implemented yet)
    # @param options [Hash] a list of available options:
    #  * port
    #  * fps
    #  * filename (pattern 'DATE' in filename will be substituted by current date_time.)
    #  * encoding [ VNCRec::ENC_RAW | VNCRec::ENC_HEXTILE ]"
    #  * pix_fmt ["bgr8" | "bgra"] (string || symbol, case insens.)
    #  * ffmpeg_iv_opts ffmpeg input video options
    #  * ffmpeg_ia_opts ffmpeg input audio options
    #  * ffmpeg_out_opts ffmpeg output options
    #  * log/logger/logging(bool) 
    #
    attr_accessor :on_exit

    def initialize(options = {})
      options = VNCRec::Recorder::DEFAULTS.merge(options)
      @logging = options[:logging] || options[:logger] || options[:log] || false
      if @logging
        @logger = Logger.new STDERR
        @logger.datetime_format = '% d_%m  %H-%M-%S.%6N'
        @logger.info options.inspect
      end

      @debug = options[:debug]
      $stderr.puts 'Debug mode' if @debug

      @port = options[:port]
      fail ArgumentError, 'Invalid port value' unless @port.is_a?(Numeric) && (1024..65_535).include?(@port)

      @host = options[:host]

      @client = nil

      @framerate = options[:fps]
      fail ArgumentError if !@framerate.is_a?(Numeric) || @framerate <= 0

      @filename = options[:filename] || (options[:port].to_s + '.raw')
      fail "Cannot create file #{@filename}" unless system "touch #{@filename}"

      if options[:geometry]
        @geometry = options[:geometry]
        fail ArgumentError, "Geometry is invalid, expected: <x>x<y>, \
          got: #{@geometry.inspect}" unless valid_geometry?(@geometry)
      end

      @enc = options[:encoding]

      pf = options[:pix_fmt].to_s.dup.prepend('PIX_FMT_').upcase.to_sym
      fail ArgumentError, "Unknown pix_fmt #{options[:pix_fmt]}" unless VNCRec.const_defined? pf
      @pix_fmt = VNCRec.const_get(pf)

      @ffmpeg_iv_opts = options[:ffmpeg_iv_opts]
      @ffmpeg_ia_opts = options[:ffmpeg_ia_opts]
      @ffmpeg_out_opts = options[:ffmpeg_out_opts]
      Thread.abort_on_exception = true
      @on_exit = [:close_file, :close_proxy]

      @file = nil
      @sleep_time = 0.01
      @recording_starttime = nil
    end

    # Start routine: wait for connection,
    # perform handshake, get data, write data.
    # Non-blocking.
    def run
      @loop = Thread.new do
        routine
      end
    end

    # Safely stop any interaction with VNC server, close file.
    # Execute all on_exit hooks.
    # @param error [Integer] exit code

    def stop
      @loop.kill unless Thread.current == @loop
      @on_exit.each do |bl|
        send bl if bl.is_a? Symbol
        bl.call if bl.respond_to?(:call)
      end
    end

    # Return current size of file
    # @return size [Integer]
    def filesize
      return @file.size if @file
      0
    end

    # Find out if main loop thread is alive.
    # @return [bool]
    def stopped?
      !(@loop.nil? && @loop.alive?)
    end

    def running?
      @loop && @loop.alive?
    end

    private

    def close_file # !FIXME
      return unless @file
      @file.close unless @file.closed?
      sleep 0.1 until @file.closed?
      substitute_filename
    end

    def substitute_filename
      File.rename(@filename,
                  @filename.gsub('DATE', '%Y_%m_%d_%Hh_%Mm_%Ss')
                 ) if @recording_starttime && @filename['DATE']
    end

    def close_proxy
      @server.close if @server && !@server.closed?
    end

    def ready_read?
      res = IO.select([@client], nil, nil, 0)
      !res.nil?
    end

    def routine

      if @host
        @logger.info "connecting to #{@host}:#{@port}" if @logging
        @server = TCPSocket.new(@host, @port)
        @logger.info 'connection established' if @logging
      else
        @logger.info 'starting server' if @logging
        @server = TCPServer.new(@port).accept
        @logger.info 'got client' if @logging

      end
      @client = VNCRec::RFB::Proxy.new(@server, 'RFB 003.008', @enc, @pix_fmt)
      @recording_starttime = Time.now if @filename.include?('DATE')

      w, h, name = @client.handshake
      @geometry ||= "#{w}x#{h}"
      parse_geometry

      @client.prepare_framebuffer(@w, @h, @pix_fmt[:bpp])
      @logger.info "server geometry: #{w}x#{h}" if @logging
      @logger.info "requested geometry: #{@w}x#{@h}" if @logging

      @file = VNCRec::Writers.get_writer(
        @filename,
        geometry: @geometry,
        fps: @framerate,
        pix_fmt: @pix_fmt[:string],
        ffmpeg_iv_opts: @ffmpeg_iv_opts,
        ffmpeg_ia_opts: @ffmpeg_ia_opts,
        ffmpeg_out_opts: @ffmpeg_out_opts)

      if name.nil?
        @logger.error 'Error in handshake' if @logging
        stop
      else
        @logger.info "Ok. Server: #{name}" if @logging
      end

      unless @client.set_encodings [@enc]
        @logger.error 'Error while setting encoding' if @logging
        stop
      end
      @client.set_pixel_format @pix_fmt
      unresponded_requests = 0
      incremental = 0
      framerate_update_counter = 1
      begin
        loop do
          if IO.select([@client.io], nil, nil, 0.05).nil?
            @client.fb_update_request(incremental, 0, 0, @w, @h) if unresponded_requests < 1
            unresponded_requests += 1
            if unresponded_requests > 250
              @logger.warn '250 unresponded requests' if @logging
              if unresponded_requests > 500
                @logger.error '500 unresponded requests' if @logging
                stop
              end
              @client.fb_update_request(0, 0, 0, @w, @h)
              sleep(0.25 + rand)
            end
          else
            unresponded_requests = 0
            if framerate_update_counter % 25 != 0
              t, data = @client.handle_response
              @logger.info "Got response: type #{t}" if @logger
            else
              adjust_sleep_time { t, data = @client.handle_response }
              framerate_update_counter = 1
              incremental = 0
            end
            case t
            when 0 then
              if data.nil?
                @logger.error 'Failed to read frame' if @logging
                stop
              else
                framerate_update_counter += 1
                incremental = 255 if incremental.zero? && framerate_update_counter > 1
              end
              @file.write data
              sleep @sleep_time
            when 1 then
              @logger.info 'Got colormap' if @logging
            when 2 then next # bell
            when 3 then
              @logger.info "Server cut text: #{data}" if @logging
            else
              @logger.error "Unknown response format: #{t}" if @logging
              stop
            end
          end
        end
      rescue EOFError, IOError
        @logger.error 'Connection lost' if @logging
        stop
      end
    end

    def adjust_sleep_time(&block)
      # figures out how much does one frame rendering takes
      # and sets instance variable according to this value
      t1 = Time.now.to_f
      block.call
      t2 = Time.now.to_f
      frt = t2 - t1
      @framerate ||= 8
      if frt > 1.0 / @framerate
        @logger.warn 'It takes too much time:' if @logging
        @logger.warn "#{frt} seconds" if @logging
        @logger.warn 'to render one frame' if @logging
        @logger.warn 'Setting idle time to 0'  if @logging
        @sleep_time = 0
        return
      end
      @sleep_time = (1.0 / @framerate) - frt - 10e-2
      @sleep_time = 0 if @sleep_time < 0
      @logger.info "Renderding of one frame takes about #{ frt } seconds" if @logging
      @logger.info "Requested framerate: #{@framerate}, sleep time is #{@sleep_time}" if @logging
    end

    def valid_geometry?(str)
      str.is_a?(String) && str[/(\d+)x(\d+)/]
    end

    def parse_geometry
      @geometry[/(\d+)x(\d+)/]
      @w = $1.to_i
      @h = $2.to_i
    end
  end
end
