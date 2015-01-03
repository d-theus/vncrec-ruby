#!/usr/bin/env ruby
# encoding: utf-8

require 'vncrec'

VNCRec::Recorder.new(
  encoding: VNCRec::EncHextile,
  filename: 'file.mp4',
  ffmpeg_out_opts: '-vcodec libx264 -preset ultrafast'
)
