require "mkmf"

extension_name = 'enchex_c'
dir_config(extension_name)
create_makefile("vncrec/rfb/#{extension_name}")
