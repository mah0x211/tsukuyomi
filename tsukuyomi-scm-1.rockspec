package = "tsukuyomi"
version = "scm-1"
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
    "lpeg=0.10.2-1",
    "lxsh"
}
build = {
    type = "builtin",
    modules = {
        util = "tsukuyomi.lua"
    }
}

