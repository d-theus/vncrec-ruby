#!/usr/bin/env ruby
# encoding: utf-8

# Authentication example.
# Currently only VNC Authentication type is supported.
# This type of auth should not be used over untrusted networks,
# because it uses DES in ECB mode.
#
# auth option is an Array. Either
# [VNCRec::RFB::Authentication::None] (default) or
# [VNCRec::RFB::Authentication::VncAuthentication, 'mypassword']

require 'vncrec'

VNCRec::Recorder.new(
  encoding: VNCRec::EncHextile,
  filename: 'file.mp4',
  auth: [VNCRec::RFB::Authentication::VncAuthentication, 'mypassword']
)

