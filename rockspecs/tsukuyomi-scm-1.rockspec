package = "tsukuyomi"
version = "scm-1"
source = {
    url = "git://github.com/mah0x211/tsukuyomi.git"
}
description = {
    summary = "lua simple template engine",
    homepage = "https://github.com/mah0x211/tsukuyomi", 
    license = "MIT/X11",
    maintainer = "Masatoshi Teruya"
}
dependencies = {
    "lua >= 5.1",
    "util",
    "halo"
}
build = {
    type = "builtin",
    modules = {
        tsukuyomi = "tsukuyomi.lua",
        ['tsukuyomi.lexer'] = "lib/lexer.lua",
        ['tsukuyomi.parser'] = "lib/parser.lua",
        ['tsukuyomi.generator'] = "lib/generator.lua"
    }
}

