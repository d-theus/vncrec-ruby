#!/usr/bin/env ruby
# encoding: utf-8

require 'vncrec'

VNCRec::Recorder.new(
  encoding: VNCRec::EncHextile,
  filename: 'file.mp4',
  ffmpeg_ia_opts: '-i /path/to/audio/file.mp3',
  ffmpeg_out_opts: '-map 0 -vcodec libx264 -preset ultrafast -map 1 -acodec mp3'
)
