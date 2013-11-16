package = "tsukuyomi"
version = "0.1-1"
source = {
    url = "git://github.com/mah0x211/tsukuyomi.git"
}
description = {
    summary = "lua simple template engine",
    detailed = [[]],
    homepage = "https://github.com/mah0x211/tsukuyomi", 
    license = "MIT/X11",
    maintainer = "Masatoshi Teruya"
}
dependencies = {
    "penlight"
}
build = {
    type = "builtin",
    modules = {
        util = "tsukuyomi.lua"
    }
}

