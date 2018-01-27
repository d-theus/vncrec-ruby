VNCRec
===========

VNCRec is a gem that provides you 
tools to record VNC session.

## Installation

`gem install vncrec`

## Usage
There is a binary called `vncrec`, which is a recorder tool.

With no host specified, it will listen on
given port (5900 by default) for connection
from VNC server (they refer to that mode as
_reverse connection_). This is intended to
be used when you want to record remote
desktop and you don't know if it's available.

Call `vncrec -h` for list of available options.
To stop recording send `SIGINT` (press ^C).

You can also use `VNCRec::Recorder` class in your ruby code.

```ruby
require 'vncrec'

r = VNCRec::Recorder.new(filename: "myvncsession.mp4")
r.run
# loop do 
#   sleep 100
# end
```

If you have FFmpeg installed, file extension is passed just through to it, so
you can specify encoder you want by passing .mp4 or .flv, etc. If no filename
specified, `vncrec` assumes raw. There is also a way to 
record raw video by specifying filename with extension .raw. This way FFmpeg is 
not required.

_NOTE:_ you should use avconv (from libav-tools) on some debian systems. Please, make
  a symlink, e.g. `ln -s /usr/bin/avconv /usr/bin/ffmpeg`.
