# Changelog

##1.0.6

* silence system which ffmpeg

##1.0.5

* Fixed popen cmdline redirection which somehow was broken on Debian jessie

##1.0.4

* Added authentication

##1.0.3

##1.0.2

* Fixed crash caused by sending `USR1` when `Writer` is not initialized
* `Rake::BuildTask` fix to exec `bundle exec rspec` and not to install gem
* Added spec for `Recorder#filesize`
