#!/usr/bin/env ruby
# encoding: utf-8

require 'vncrec'

r = VNCRec::Recorder.new
#  Append exit to the list of on_exit hooks.
r.on_exit.push(->() { exit })
