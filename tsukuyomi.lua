--[[

    tsukuyomi.lua
    Created by Masatoshi Teruya on 13/11/15.
    
    Copyright 2013 Masatoshi Teruya. All rights reserved.
    
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
local lexer = require('pl.lexer');
local PRIVATE_IDEN = {};
PRIVATE_IDEN['_G'] = true;
PRIVATE_IDEN['__TSUKUYOMI__'] = true;
PRIVATE_IDEN['__RES__'] = true;
PRIVATE_IDEN['__DATA__'] = true;
PRIVATE_IDEN['__IGNORE_NILOPS__'] = true;

-- change nil metatable
local function nilOps( op1, op2 )
    return op1 or op2;
end

local function nilLen()
    return 0;
end

-- ignore nil operation
local function ignoreNilOps( ignore )
    local meta = {};
    
    if ignore then
        meta.__index = function()
            return nil;
        end
        meta.__newindex = function()
            return nil;
        end
        meta.__concat = nilOps;
        meta.__add = nilOps;
        meta.__sub = nilOps;
        meta.__mul = nilOps;
        meta.__div = nilOps;
        meta.__mod = nilOps;
        meta.__len = nilLen;
        debug.setmetatable( nil, meta );
    else
        debug.setmetatable( nil, meta );
    end
end

-- Stack class(metatable)
local Stack = {};

-- methods
function Stack:push( arg )
    table.insert( self, arg );
end

function Stack:pop( arg )
    return table.remove( self );
end

-- create Stack instance
function Stack.new()
    return setmetatable( {}, {
        __index = Stack
    });
end

local function tableKeys( tbl )
    local list = {};
    local idx = 1;
    for k in pairs( tbl ) do
        list[idx] = k;
        idx = idx + 1;
    end
    
    return list, idx - 1;
end

-- find lineno and position
local function linepos( src, head, tail )
    local str = src:sub( 1, head );
    local originHead = head;
    local lineno = 1;
    local pos = 1;
    
    head, tail = string.find( str, '\n', 1, true );
    
    while head do
        pos = tail;
        lineno = lineno + 1;
        head, tail = string.find( str, '\n', tail + 1, true );
    end
    pos = originHead - pos;
    
    return lineno, pos;
end

-- generate error string
local function errstr( tag, msg )
    return '[line:' .. tag.lineno .. ':' .. tag.pos .. '] ' .. 
            ( msg or '' ) .. 
            ' ::' .. tag.token .. '::';
end


-- generate error string with source mapping table
local function errmap( srcmap, err )
    local idx, msg;
    
    -- find error position
    idx, msg = string.match( err, ':(%d+):(.*)' );
    if idx then
        idx = tonumber( idx );
        return errstr( srcmap[idx], msg );
    end
    
    return err;
end

-- compile script
local function compile( ctx, env )
    local src, script, err, msg, len;
    
    -- append local variables
    ctx.local_decl, len = tableKeys( ctx.local_decl );
    if len > 0 then
        ctx.tag_decl[2].token = 'local ' .. table.concat( ctx.local_decl, ', ' ) .. ';';
        ctx.code[2] = ctx.tag_decl[2].token;
    end
    
    -- append return code
    table.insert( ctx.code, 'return __TSUKUYOMI__:table_join( __RES__ );' );
    
    -- add end mark of function block
    table.insert( ctx.code, 'end' );
    
    -- generate script source
    src = table.concat( ctx.code, '\n' );
    
    -- compile
    script, err = load( src, src, 't', env );
    -- got error
    if err then
        -- find error position
        err = errmap( ctx.tag_decl, err );
    else
        script = script();
    end
    
    return script, err;
end

-- tag parser
local function findTag( ctx )
    local txt = ctx.txt;
    local caret = ctx.caret;
    local head, tail = string.find( txt, '<?', caret, true );
    local ignore = false;
    local quot, tag, word, lineno, pos;
    
    while head do
        tail = tail + 1;
        word = txt:sub( tail, tail );
        -- ignore if after whitespace:0x20
        if word == ' ' then
            quot = nil;
            goto CONTINUE;
        -- found open bracket
        else
            tag = { head = head - 1 };
            skipSP = false;
            -- search close bracket ?>:[0x3F][0x3E]
            while word ~= '' do
                -- found quot: [", '] and not escape sequence: [\] at front
                if ( word == '"' or word == '\'' ) and 
                    txt:byte(tail-1) ~= 0x5C then
                    -- clear current quot if close quot
                    if quot == word then
                        quot = nil;
                    -- set current quot if not in quot
                    else
                        quot = word;
                    end
                -- not in quot and found close bracket
                elseif not quot and word == '?' and txt:byte(tail+1) == 0x3E then
                    tail = tail + 1;
                    break;
                end
                tail = tail + 1;
                word = txt:sub( tail, tail );
            end
        end
        
        -- close bracket not found
        -- missing end of bracket
        if word == '' then
            break;
        -- create tag struct
        else
            tag.tail = tail;
            -- trim /^\s|\s$/g
            tag.token = string.match( 
                -- remove \n
                string.gsub( txt:sub( head + 2, tail - 2 ), '(\n+)', '' ),
                '([^%s].+[^%s])'
            );
            -- separate NAME, SP, EXPR
            tag.name, word, tag.expr = string.match( tag.token, '^(%g+)(%s*)(.*)' );
            -- set nil to empty
            if tag.expr == '' then
                tag.expr = nil;
            end
            tag.lineno, tag.pos = linepos( txt, tag.head, tag.tail );
            break;
        end
        
        ::CONTINUE::
        head, tail = string.find( txt, '<?', tail, true );
    end
    
    return tag;
end

-- analyze
local ACCEPT_KEYS = {};
ACCEPT_KEYS['true'] = true;
ACCEPT_KEYS['false'] = true;
ACCEPT_KEYS['nil'] = true;
ACCEPT_KEYS['and'] = true;
ACCEPT_KEYS['or'] = true;
ACCEPT_KEYS['not'] = true;
ACCEPT_KEYS['in'] = true;

local function analyze( ctx, tag )
    -- tokenize
    local stack = Stack.new();
    local state = {
        iden = false
    };
    local token = {};
    local idx = 1;
    local k, v;
    
    for k,v in lexer.lua( tag.expr ) do
        -- found string
        if k == 'string' then
            v = "'" .. v .. "'";
        -- found data variable prefix
        elseif k == '@' then
            token[idx] = '__DATA__.';
            state.prev = '.';
            state.iden = true;
            goto CONTINUE;
        -- found identifier
        elseif k == 'iden' then
            -- not member fields
            if state.prev ~= '.' then
                -- private ident
                if PRIVATE_IDEN[v] then
                    return nil, nil, errstr( tag, 'cannot access to private variable:' .. v );
                -- to declare to local if identifier does not exists at environment
                elseif not ctx.env[v] then
                    ctx.local_decl[v] = true;
                end
                state.iden = true;
                v = ' ' .. v;
            end
        -- found open-bracket
        elseif k == '[' then
            if state.iden then
                -- save current state
                stack:push( state );
                state = {
                    iden = false;
                };
            end
        -- found close-bracket
        elseif k == ']' then
            state = stack:pop();
        -- found not member operator
        elseif k ~= '.' then
            state.iden = false;
            if k == 'keyword' then
                if not ACCEPT_KEYS[v] then
                    return nil, nil, errstr( tag, 'invalid syntax' );
                end
                v = ' ' .. v .. ' ';
            elseif k == '=' or k == '..' then
                v = ' ' .. v .. ' ';
            end
        end
        
        state.prev = k;
        token[idx] = v;
        
        ::CONTINUE::
        idx = idx + 1;
    end
    
    return token, idx - 1;
end

-- generate source lines of code
local VOIDTXT_TBL = {};
VOIDTXT_TBL['\n'] = '\\n';
VOIDTXT_TBL['\''] = '\\\'';
VOIDTXT_TBL['\\'] = '\\\\';

local function pushText( ctx, tail )
    -- void [\n, ', \]
    local voidtxt = string.gsub( 
        ctx.txt:sub( ctx.caret, tail ), 
        '[\n\'\\]', 
        VOIDTXT_TBL 
    );
    local lineno, pos = linepos( ctx.txt, ctx.caret, tail );
    
    -- add tag index
    table.insert( ctx.tag_decl, {
        lineno = lineno,
        pos = pos
    });
    
    table.insert( 
        ctx.code, '__RES__[#__RES__+1] = \'' .. voidtxt .. '\';'
    );

end

-- then: if, elseif
local function slocThen( ctx, tag )
    local token, len, err = analyze( ctx, tag );
    
    if not err then
        table.insert( ctx.code, tag.name .. ' ' .. table.concat( token ) .. ' then' );
    end
    
    return err;
end

-- do: for, while
local function slocDo( ctx, tag )
    local token, len, err = analyze( ctx, tag );
    
    if not err then
        table.insert( ctx.code, tag.name .. ' ' .. table.concat( token ) .. ' do' );
    end
    
    return err;
end

-- none: else, end
local function slocNone( ctx, tag )
    local err = tag.expr and errstr( tag, 'invalid arguments' );
    
    if not err then
        table.insert( ctx.code, tag.name );
    end
    
    return err;
end

-- goto
local function slocGoto( ctx, tag )
    local token, len, err = analyze( ctx, tag );
    
    if not err then
        if len ~= 1 then
            err = errstr( tag, 'invalid arguments' );
        else
            table.insert( ctx.code, tag.name .. ' ' .. token[1] .. ';' );
        end
    end
    
    return err;
end

-- label
local function slocLabel( ctx, tag )
    local token, len, err = analyze( ctx, tag );
    
    if not err then
        if len ~= 1 then
            err = errstr( tag, 'invalid arguments' );
        else
            table.insert( ctx.code, '::' .. token[1] .. '::' );
        end
    end
    
    return err;
end

-- put
local function slocPut( ctx, tag )
    local token, len, err = analyze( ctx, tag );
    
    if not err then
        table.insert( 
            ctx.code, '__RES__[#__RES__+1] = ' .. table.concat( token ) .. ';' 
        );
    end
    
    return err;
end

-- insert
local function slocInsert( ctx, tag )
    local token, len, err = analyze( ctx, tag );
    
    if not err then
        if len ~= 1 then
            err = errstr( tag, 'invalid arguments' );
        else
            ctx.insertions[ string.match( token[1], '([^\'].+[^\'])' ) ] = true;
            table.insert( 
                ctx.code, 
                '__RES__[#__RES__+1] = __TSUKUYOMI__:recite(' .. 
                token[1] .. 
                ', __DATA__, __IGNORE_NILOPS__);'
            );
        end
    end
    
    return err;
end

local SLOC = {};
SLOC['if'] = slocThen;
SLOC['elseif'] = slocThen;
SLOC['else'] = slocNone;
SLOC['for'] = slocDo;
SLOC['while'] = slocDo;
SLOC['break'] = slocNone;
SLOC['end'] = slocNone;
SLOC['goto'] = slocGoto;
SLOC['label'] = slocLabel;
-- custom tags
SLOC['put'] = slocPut;
SLOC['insert'] = slocInsert;

-- read template context
local function parse( ctx )
    local err;
    
    if ctx.length ~= '' then
        local code = ctx.code;
        local tag, sloc;
        
        -- find tag
        tag = findTag( ctx );
        while tag do
            -- no close bracket: ?>
            if not tag.tail then
                return 'could not found closed-bracket';
            -- push plain text
            elseif ctx.caret <= tag.head then
                pushText( ctx, tag.head );
            end
            
            -- get handler
            sloc = SLOC[tag.name];
            if sloc then
                table.insert( ctx.tag_decl, tag );
                err = sloc( ctx, tag );
                if err then
                    goto DONE;
                end
            else
                err = 'unknown expr: ' .. tag.name;
                goto DONE;
            end
            
            -- move caret
            ctx.caret = tag.tail + 1;
            -- remove index and expr
            tag.name = nil;
            tag.expr = nil;
            tag.head = nil;
            tag.tail = nil;
            -- find next tag
            tag = findTag( ctx );
        end
        
        -- push remain text
        if ctx.caret < ctx.length then
            pushText( ctx, ctx.length );
        end
    end
    
    ::DONE::
    return err;
end



-- tsukuyomi instance methods(metatable)
local tsukuyomi = {};

function tsukuyomi:recite( label, ignoreNil, data )
    local page = self.pages[label];
    local res = {};
    local co, success, val;
    
    if page then
        -- enable ignore nil operation switch
        if ignoreNil then
            ignoreNilOps( true );
        end
        -- invoke script by coroutine
        co = coroutine.create( page.script );
        success, val = coroutine.resume( co, self, res, data or {}, ignoreNil );
        -- disable ignore nil operation switch
        if ignoreNil then
            ignoreNilOps( false );
        end
        
        if not success and page.srcmap then
            val = errmap( page.srcmap, val );
        end
    else
        val = '[' .. label .. ' not found]';
    end
    
    return val, success;
end

function tsukuyomi:table_join( arr, sep )
    local res = {};
    local k,v = next( arr );
    local t;
    
    -- traverse table as array
    while k do
        t = type( v );
        if t == 'string' or t == 'number' then
            table.insert( res, v );
        elseif t == 'boolean' then
            table.insert( res, tostring( v ) );
        else
            table.insert( res, '[' .. tostring( v ) .. ']' );
        end
        k,v = next( arr, k );
    end
    
    return table.concat( res, sep );
end

-- class methods
-- create instance
local function tsukuyomi_new( env )
    return setmetatable({
        env = ( type( env ) == 'table' ) and env or _G,
        pages = {}
    }, {
        __index = tsukuyomi
    });
end

-- read template context
local function tsukuyomi_read( t, label, txt, srcmap )
    local ctx = {
        env = t.env or {},
        caret = 1,
        txt = txt,
        length = string.len( txt ),
        code = {},
        local_decl = {},
        insertions = {},
        tag_decl = {
            {
                lineno = -1,
                pos = 0,
                token = 'return function( __TSUKUYOMI__, __RES__, __DATA__, __IGNORE_NILOPS__ )'
            },
            {
                lineno = -1,
                pos = 0,
                token = ''
            }
        }
    };
    local script, err, insertions;
    
    ctx.code[1] = ctx.tag_decl[1].token;
    ctx.code[2] = ctx.tag_decl[2].token;
    
    -- parse text
    err = parse( ctx );
    if not err then
        -- compile context
        script, err = compile( ctx, t.env );
        if not err then
            -- add page
            t.pages[label] = {
                script = script,
                srcmap = srcmap and ctx.tag_decl or nil
            };
            insertions = ctx.insertions;
        end
    end
    
    return err, insertions;
end

return {
    new = tsukuyomi_new,
    read = tsukuyomi_read
};
