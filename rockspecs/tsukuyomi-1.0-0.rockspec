package = "tsukuyomi"
version = "1.0-0"
source = {
    url = "git://github.com/mah0x211/tsukuyomi.git",
    tag = "v1.0.0"
}
description = {
    summary = "lua simple template engine",
    detailed = [[]],
    homepage = "https://github.com/mah0x211/tsukuyomi", 
    license = "MIT/X11",
    maintainer = "Masatoshi Teruya"
}
dependencies = {
    "lua >= 5.1",
    "util >= 1.0",
    "halo >= 1.0"
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

