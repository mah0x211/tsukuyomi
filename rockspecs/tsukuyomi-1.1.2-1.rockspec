package = "tsukuyomi"
version = "1.1.2-1"
source = {
    url = "git://github.com/mah0x211/tsukuyomi.git",
    tag = "v1.1.2"
}
description = {
    summary = "lua simple template engine",
    homepage = "https://github.com/mah0x211/tsukuyomi",
    license = "MIT/X11",
    maintainer = "Masatoshi Teruya"
}
dependencies = {
    "lua >= 5.1",
    "util >= 1.2.0",
    "halo >= 1.1.0"
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

