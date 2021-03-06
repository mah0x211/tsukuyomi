--[[

    parser.lua
    Created by Masatoshi Teruya on 14/06/20.

    Copyright 2014 Masatoshi Teruya. All rights reserved.

    Permission is hereby granted, free of charge, to any person obtaining a copy
    of this software and associated documentation files (the "Software"), to deal
    in the Software without restriction, including without limitation the rights
    to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
    copies of the Software, and to permit persons to whom the Software is
    furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice shall be included in
    all copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.  IN NO EVENT SHALL THE
    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
    THE SOFTWARE.

--]]
local Parser = require('halo').class.Parser;

local TAGNAME_SKIP = {
    ['if'] = 2,
    ['elseif'] = 2,
    ['else'] = 2,
    ['for'] = 2,
    ['while'] = 2,
    ['break'] = 2,
    ['end'] = 2,
    ['insert'] = 2,
    ['goto'] = 2,
    ['label'] = 2,
    ['code'] = 2
};
local LF = 0xA;
local BACKSLASH = 0x5C;


-- find lineno and position
local function linepos( src, head )
    local str = src:sub( 1, head );
    local originHead = head;
    local lineno = 1;
    local pos = 1;
    local tail;

    head, tail = string.find( str, '\n', 1, true );

    while head do
        pos = tail;
        lineno = lineno + 1;
        head, tail = string.find( str, '\n', tail + 1, true );
    end
    pos = originHead - pos;

    return lineno, pos;
end

-- tag parser
local SYM_QUOT = {
    ['\''] = true,
    ['"'] = true
};

local function findTagClose( tagClose, txt, len, cur )
    local c, head, tail;

    -- search close bracket ?>:[0x3F][0x3E]
    while cur < len do
        c = txt:sub( cur, cur );
        -- check literal-bracket(double-bracket)
        if c == '[' then
            head, tail = txt:find( '^%[=*%[', cur );
            -- found open literal-bracket
            if head then
                -- find close literal-bracket
                c = txt:sub( head, tail ):gsub( '%[', '%]' );
                head, tail = txt:find( c, tail + 1, true );
                -- invalid syntax
                if not head then
                    break;
                end
                -- skip literal bracket
                cur = tail + 1;
            -- move to next index
            else
                cur = cur + 1;
            end
        -- found quot: [", '] and not escape sequence: [\] at front
        elseif SYM_QUOT[c] and txt:byte( cur - 1 ) ~= BACKSLASH then
            head, tail = txt:find( '[^\\]' .. c, cur );
            -- invalid syntax
            if not head then
                break;
            end
            -- skip quot
            cur = tail + 1;
        -- found close bracket
        elseif txt:sub( cur, cur + 1 ) == tagClose then
            return cur + 1;
        -- move to next index
        else
            cur = cur + 1;
        end
    end

    return nil;
end

--[[
    {
        head = number,
        tail = number,
        lineno = number,
        pos = number,
        name = string,
        expr = string or nil
    }
]]
local function findTag( tagOpen, tagClose, txt, len, caret )
    local head, htail = txt:find( tagOpen, caret );
    local tag, tail, token, name, sym;

    -- found open bracket
    if head then
        tag = { head = head - 1 };
        tag.lineno, tag.pos = linepos( txt, head - 1 );
        tail = findTagClose( tagClose, txt, len, htail + 1 );
        -- found close bracket
        if tail then
            -- create tag struct
            tag.tail = tail;
            -- separate helper command symbol
            sym, name = txt:sub( head + 2, htail ):match( '^([%$]*)(.+)$' );
            -- no symbol
            if sym == '' then
                tag.name = name;
            else
                tag.name = 'helper';
                tag.cmd = name;
            end

            token = txt:sub( htail + 1, tail - 2 );
            -- check expression
            if not token:find('^%s*$') then
                -- expression must have space at head
                if not token:find('^%s') then
                    tag.tail = nil;
                else
                    -- remove \n ^%s %s$
                    tag.expr = token:gsub( '(\n*)', '' )
                                    :gsub( '^%s+', '' )
                                    :gsub( '%s+$', '' );
                end
            end
        end
    end

    return tag;
end

-- generate source lines of code
local VOIDTXT_TBL = {};
VOIDTXT_TBL['\n'] = '\\n';
VOIDTXT_TBL['\''] = '\\\'';
VOIDTXT_TBL['\\'] = '\\\\';
local function txtTag( txt, caret, tail )
    local plainTxt = txt:sub( caret, tail );
    -- void [\n, ', \]
    local voidtxt = string.gsub( plainTxt, '[\n\'\\]', VOIDTXT_TBL );
    local lineno, pos = linepos( txt, caret );

    return {
        head = caret,
        tail = tail,
        lineno = lineno,
        pos = pos,
        expr = '\'' .. voidtxt .. '\'',
        name = 'txt'
    };
end


Parser:property {
    protected = {
        useBraces = false,
        tagOpen = '<%?[$]*[%a]+',
        tagClose = '?>'
    }
};


function Parser:init( useBraces )
    local cfg = protected( self );

    if useBraces then
        assert(
            type( useBraces ) == 'boolean',
            'useBraces must be type of boolean'
        );
        cfg.tagOpen = '{{[$]*[%a]+';
        cfg.tagClose = '}}';
    end

    return self;
end


-- read template context
function Parser:parse( txt, nolf )
    local cfg = protected( self );
    local tagOpen = cfg.tagOpen;
    local tagClose = cfg.tagClose;
    local tags = {};
    local idx = 0;
    local len = string.len( txt );

    if len > 0 then
        local caret = 1;
        local tag;

        -- find tag
        tag = findTag( tagOpen, tagClose, txt, len, caret );
        while tag do
            idx = idx + 1;
            -- push plain text
            if caret <= tag.head then
                if tag.name == 'end' and txt:byte( tag.head ) == LF then
                   tags[idx] = txtTag( txt, caret, tag.head - 1 );
                else
                   tags[idx] = txtTag( txt, caret, tag.head );
                end
                idx = idx + 1;
            end

            -- insert tag
            tags[idx] = tag;
            -- no close bracket: ?>
            if not tag.tail then
                caret = len;
                break;
            end

            -- move caret
            -- remove LF
            if nolf == true and txt:byte( tag.tail + 1 ) == LF then
                caret = tag.tail + ( TAGNAME_SKIP[tag.name] or 1 );
            else
                caret = tag.tail + 1;
            end

            -- find next tag
            tag = findTag( tagOpen, tagClose, txt, len, caret );
        end

        -- push remain text
        if caret < len then
            idx = idx + 1;
            tags[idx] = txtTag( txt, caret, len );
        end
    end

    return tags, idx;
end


return Parser.exports;
