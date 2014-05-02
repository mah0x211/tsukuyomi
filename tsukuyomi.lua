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
local lexer = require('tsukuyomi.lexer');
local PRIVATE_IDEN = {};
PRIVATE_IDEN['_G'] = true;
PRIVATE_IDEN['__TSUKUYOMI__'] = true;
PRIVATE_IDEN['__RES__'] = true;
PRIVATE_IDEN['__DATA__'] = true;

-- change nil metatable
local function nilIdx()
    return nil;
end

local function nilOps( op1, op2 )
    return op1 or op2;
end

local function nilLen()
    return 0;
end

local METATBL_NIL = {
    __index = nilIdx,
    __newindex = nilIdx,
    __concat = nilOps,
    __add = nilOps,
    __sub = nilOps,
    __mul = nilOps,
    __div = nilOps,
    __mod = nilOps,
    __pow = nilOps,
    __unm = nilOps,
    __len = nilLen
};
local METATBL_EMPTY = {};

-- ignore nil operation
local function ignoreNilOps( ignore )
    if ignore then
        debug.setmetatable( nil, METATBL_NIL );
    else
        debug.setmetatable( nil, METATBL_EMPTY );
    end
end


-- Stack class(metatable)
local Stack = {};

-- methods
function Stack:push( arg )
    table.insert( self, arg );
end


function Stack:pop()
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


-- generate error string
local function errstr( tag, msg, label )
    return '[line:' .. tag.lineno .. ':' .. tag.pos .. '' .. 
            ( label and ':' .. label or '' ) .. '] ' .. 
            ( msg or '' ) .. 
            ( tag.token and ' ::' .. tag.token .. '::' or '' );
end


-- generate error string with source mapping table
local function errmap( srcmap, err, label )
    -- find error position
    local idx, msg = string.match( err, ':(%d+):(.*)' );
    
    if idx then
        idx = tonumber( idx );
        if srcmap[idx] then
            return errstr( srcmap[idx], msg, label );
        end
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
    table.insert( ctx.code, 'return __RES__;' );
    
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
    
    return err, script;
end


-- tag parser
local SYM_QUOT = {
    ['\''] = true,
    ['"'] = true
};


local function findTagClose( txt, len, cur )
    local c, idx, head, tail;
    
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
                head, tail = txt:find( literal, tail + 1, true );
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
        elseif SYM_QUOT[c] and txt:byte( cur - 1 ) ~= 0x5C then
            head, tail = txt:find( '[^\\]' .. c, cur );
            -- invalid syntax
            if not head then
                break;
            end
            -- skip quot
            cur = tail + 1;
        -- found close bracket
        elseif c == '?' and txt:byte( cur + 1 ) == 0x3E then
            return cur + 1;
        -- move to next index
        else
            cur = cur + 1;
        end
    end
    
    return nil;
end


local function findTag( ctx )
    local txt = ctx.txt;
    local head, tail = string.find( txt, '<%?[$%l%u]', ctx.caret );
    local tag, word;
    
    -- found open bracket
    if head then
        tag = { head = head - 1 };
        tag.lineno, tag.pos = linepos( txt, tag.head );
        tail = findTagClose( txt, ctx.length, tail + 1 );
        -- found close bracket
        if tail then
            -- create tag struct
            tag.tail = tail;
            -- trim /^\s|\s$/g
            tag.token = string.match( 
                -- remove \n
                string.gsub( txt:sub( head + 2, tail - 2 ), '(\n+)', '' ),
                '([^%s].+[^%s])'
            );
            -- separate NAME, SP, EXPR
            tag.name, word, tag.expr = string.match( tag.token, '^([$]?[%l%u]+)(%s*)(.*)' );
            -- set nil to empty
            if tag.expr == '' then
                tag.expr = nil;
            end
        end
    end
    
    return tag;
end


-- analyze
local ACCEPT_KEYS = {};
ACCEPT_KEYS['in'] = true;
ACCEPT_KEYS['nil'] = true;
ACCEPT_KEYS['true'] = true;
ACCEPT_KEYS['false'] = true;

--TODO: should check tag context.
local function analyze( ctx, tag )
    if tag.expr then
        -- tokenize
        local stack = Stack.new();
        local state = {
            iden = false
        };
        local token = {};
        local idx = 1;
        local skipContext = false;
        local head, tail, k, v;
        
        for head, tail, k, v in lexer.scan( tag.expr ) do
            if k == lexer.T_EPAIR then
                return errstr( tag, 'unexpected symbol:' .. v );
            elseif k == lexer.T_KEYWORD then
                if not ACCEPT_KEYS[v] then
                    return errstr( tag, 'invalid keyword: ' .. v );
                end
            elseif k == lexer.T_UNKNOWN then
                -- found data variable prefix
                -- not member fields
                if v == '$' and state.prev ~= '.' and state.prev ~= ':' then
                    token[idx] = '__DATA__';
                    state.iden = true;
                    skipContext = true;
                else
                    return errstr( tag, 'unexpected symbol:' .. v );
                end
            -- found identifier
            elseif k == lexer.T_VAR then
                -- not member fields
                if state.prev ~= '.' and state.prev ~= ':' then
                    -- private ident
                    if PRIVATE_IDEN[v] then
                        return errstr( tag, 'cannot access to private variable:' .. v );
                    -- to declare to local if identifier does not exists at environment
                    elseif not ctx.env[v] then
                        ctx.local_decl[v] = true;
                    end
                    state.iden = true;
                end
            -- found open-bracket
            elseif v == '[' then
                -- save current state
                stack:push( state );
                state = {
                    iden = false;
                };
            -- found close-bracket
            elseif v == ']' then
                if #stack == 0 then
                    return errstr( tag, 'invalid syntax: ' .. v );
                end
                state = stack:pop();
            -- found not member operator
            elseif v ~= '.' then
                state.iden = false;
                -- disallow termination symbol
                if v == ';' then
                    return errstr( tag, 'invalid syntax: ' .. v );
                end
            end
            
            if skipContext then
                skipContext = false;
            else
                state.prev = v;
                token[idx] = v;
            end
            
            idx = idx + 1;
        end
        
        return nil, token, idx - 1;
    end
    
    return errstr( tag, 'too few arguments: ' .. tostring(expr) );
end

-- generate source lines of code
local VOIDTXT_TBL = {};
VOIDTXT_TBL['\n'] = '\\n';
VOIDTXT_TBL['\''] = '\\\'';
VOIDTXT_TBL['\\'] = '\\\\';

local function appendCode( ctx, tag, code )
    -- ignore source code if block_break is true.
    if not ctx.block_break then
        table.insert( ctx.tag_decl, tag );
        table.insert( ctx.code, code );
    end
end

local function pushText( ctx, tail )
    -- void [\n, ', \]
    local voidtxt = string.gsub( 
        ctx.txt:sub( ctx.caret, tail ), 
        '[\n\'\\]', 
        VOIDTXT_TBL 
    );
    local lineno, pos = linepos( ctx.txt, ctx.caret );
    
    -- add tag index
    appendCode( ctx, {
        lineno = lineno,
        pos = pos
    }, '__RES__ = __RES__ .. \'' .. voidtxt .. '\';' );

end

-- if
local function slocIf( ctx, tag )
    local err, token, len = analyze( ctx, tag );
    
    if not err then
        ctx.block_stack:push( tag );
        appendCode( ctx, tag, 
                    tag.name .. ' ' .. table.concat( token ) .. ' then' );
    end
    
    return err;
end

-- elseif
local function slocElseif( ctx, tag )
    local err, token, len = analyze( ctx, tag );
    
    if not err then
        appendCode( ctx, tag, 
                    tag.name .. ' ' .. table.concat( token ) .. ' then' );
    end
    
    return err;
end

-- do: for, while
local function slocDo( ctx, tag )
    local err, token, len = analyze( ctx, tag );
    
    if not err then
        ctx.block_stack:push( tag );
        appendCode( ctx, tag, 
                    tag.name .. ' ' .. table.concat( token ) .. ' do' );
    end
    
    return err;
end

-- else
local function slocElse( ctx, tag )
    local err = tag.expr and errstr( tag, 'invalid arguments' );
    
    if not err then
        appendCode( ctx, tag, tag.name );
    end
    
    return err;
end

-- end
local function slocEnd( ctx, tag )
    local err = tag.expr and errstr( tag, 'invalid arguments' );
    
    if not err then
        if #ctx.block_stack < 1 then
            err = errstr( tag, 'invalid statement' );
        else
            ctx.block_stack:pop();
            ctx.block_break = false;
            appendCode( ctx, tag, tag.name );
        end
    end
    
    return err;
end

-- goto
local function slocGoto( ctx, tag )
    local err, token, len = analyze( ctx, tag );
    
    if not err then
        if len ~= 1 then
            err = errstr( tag, 'invalid arguments' );
        else
            appendCode( ctx, tag, tag.name .. ' ' .. token[1] .. ';' );
        end
    end
    
    return err;
end

-- label
local function slocLabel( ctx, tag )
    local err, token, len = analyze( ctx, tag );
    
    if not err then
        if len ~= 1 then
            err = errstr( tag, 'invalid arguments' );
        else
            appendCode( ctx, tag, '::' .. token[1] .. '::' );
        end
    end
    
    return err;
end

-- put
local function slocPut( ctx, tag )
    local err, token, len = analyze( ctx, tag );
    
    if not err then
        appendCode( ctx, tag,
                    '__RES__ = __RES__ .. __TSUKUYOMI__:tostring( ' .. 
                    table.concat( token ) .. ' );' );
    end
    
    return err;
end

-- insert
local function slocInsert( ctx, tag )
    local err, token, len = analyze( ctx, tag );
    
    if not err then
        if len ~= 1 then
            err = errstr( tag, 'invalid arguments' );
        else
            local name = token[1]:match( '^[\'"](.*)[\'"]$' );
            
            if name then
                ctx.insertions[name] = true;
            end
            
            if not err then
                appendCode( ctx, tag, 
                            '__RES__ = __RES__ .. __TSUKUYOMI__:render(' .. 
                            token[1] .. ', __DATA__, false, __LABEL__ );' );
            end
        end
    end
    
    return err;
end

-- code
local function slocCode( ctx, tag )
    local err, token, len = analyze( ctx, tag );
    
    if not err then
        appendCode( ctx, tag, table.concat( token ) .. ';' );
    end
    
    return err;
end

-- break
local function slocBreak( ctx, tag )
    local err = tag.expr and errstr( tag, 'invalid arguments' );
    
    if not err then
        appendCode( ctx, tag, tag.name .. ';' );
        ctx.block_break = true;
    end
    
    return err;
end

-- custom command
local function slocCustom( ctx, tag )
    local err, token, len = analyze( ctx, tag );
    
    if not err then
        local cmd = ctx.cmds[tag.name];
        local expr = table.concat( token );
        
        -- invoke custom command and output result
        if cmd.enableOutput then
            appendCode( 
                ctx, tag, 
                '__RES__ = __RES__ .. __TSUKUYOMI__:tostring( __TSUKUYOMI__.cmds["' .. 
                cmd.name .. '"].fn(' .. expr .. ') );'
            );
        -- invoke custom command
        else
            appendCode( 
                ctx, tag,
                '__TSUKUYOMI__.cmds["' .. cmd.name .. '"].fn(' .. expr .. ');'
            );
        end
    end
    
    return err;
    
end

local SLOC = {};
SLOC['if'] = slocIf;
SLOC['elseif'] = slocElseif;
SLOC['else'] = slocElse;
SLOC['for'] = slocDo;
SLOC['while'] = slocDo;
SLOC['break'] = slocBreak;
SLOC['end'] = slocEnd;
SLOC['goto'] = slocGoto;
SLOC['label'] = slocLabel;
-- custom tags
SLOC['put'] = slocPut;
SLOC['insert'] = slocInsert;
SLOC['code'] = slocCode;

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
                return errstr( tag, 'could not found closed-bracket' );
            -- push plain text
            elseif ctx.caret <= tag.head then
                pushText( ctx, tag.head );
            end
            
            -- get handler
            sloc = SLOC[tag.name];
            -- check custom command list
            if not sloc and ctx.cmds[tag.name] then
                sloc = slocCustom;
            end
            
            if sloc then
                err = sloc( ctx, tag );
                if err then
                    break;
                end
            else
                return errstr( tag, 'unknown expr: ' .. tag.name );
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
        if not err and ctx.caret < ctx.length then
            pushText( ctx, ctx.length );
        end
    end
    
    if not err and #ctx.block_stack > 0 then
        return errstr( ctx.block_stack:pop(), 
                       'end of block statement not found' );
    end
    
    return err;
end



-- tsukuyomi instance methods(metatable)
local tsukuyomi = {};

function tsukuyomi:render( label, data, ignoreNil, parent )
    local success = false;
    local val;
    
    if type( label ) ~= 'string' then
        val = '[label must be type of string: ' .. tostring(label) .. ']';
    elseif label == parent then
        val = '[' .. label .. ': circular insertion disallowed]';
    else
        local page = self.pages[label];
        local res = '';
        
        if page then
            -- invoke script by coroutine
            local co;
            
            -- enable ignore nil operation switch
            if ignoreNil then
                ignoreNilOps( true );
            end
            
            co = coroutine.create( page.script );
            success, val = coroutine.resume( co, self, res, data or {}, label );
            
            -- disable ignore nil operation switch
            if ignoreNil then
                ignoreNilOps( false );
            end
            
            if not success and page.srcmap then
                val = errmap( page.srcmap, val, label );
            end
        else
            val = '[template:' .. label .. ' not found]';
        end
    end
    
    return val, success;
end


function tsukuyomi:tostring( ... )
    local res = '';
    local i,v,t;
    
    -- traverse table as array
    for i,v in pairs({...}) do
        t = type( v );
        if t == 'string' or t == 'number' then
            res = res .. v;
        elseif t == 'boolean' then
            res = res .. tostring( v );
        else
            res = res .. '[' .. tostring( v ) .. ']';
        end
    end
    
    return res;
end


-- class methods
-- create instance
local function tsukuyomi_new( env )
    return setmetatable({
        env = ( type( env ) == 'table' ) and env or _G,
        cmds = {},
        pages = {}
    }, {
        __index = tsukuyomi
    });
end


local PREFIX_CMD = '$';
-- set custom user command
local function tsukuyomi_cmd_set( t, cmd, fn, enableOutput )
    if type( cmd ) ~= 'string' then
        error( 'invalid argument: cmd must be type of string' );
    elseif type( fn ) ~= 'function' then
        error( 'invalid argument: fn must be type of function' );
    end
    
    -- set custom command prefix
    cmd = PREFIX_CMD .. cmd;
    if t.cmds[cmd] then
        error( 'invalid argument: ' .. cmd .. ' already exists' );
    -- set custom command
    else
        t.cmds[cmd] = {
            name = cmd,
            fn = fn,
            enableOutput = enableOutput and true or false
        };
    end
end

-- unset custom user command
local function tsukuyomi_cmd_unset( t, cmd )
    if type( cmd ) == 'string' then
        t.cmds[PREFIX_CMD .. cmd] = nil;
    end
end

-- remove template context
local function tsukuyomi_remove( t, label )
    if t.pages[label] then
        t.pages[label] = nil;
    end
end

-- read template context
local function tsukuyomi_read( t, label, txt, enableSourceMap )
    local ctx = {
        env = t.env or {},
        cmds = t.cmds,
        caret = 1,
        txt = txt,
        length = string.len( txt ),
        code = {},
        local_decl = {},
        insertions = {},
        block_stack = Stack.new(),
        tag_decl = {
            {
                lineno = -1,
                pos = 0,
                token = 'return function( __TSUKUYOMI__, __RES__, __DATA__, __LABEL__ )'
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
        err, script = compile( ctx, t.env );
        if not err then
            -- add page
            t.pages[label] = {
                script = script,
                srcmap = enableSourceMap and ctx.tag_decl or nil
            };
            insertions = ctx.insertions;
        end
    end
    
    return err, insertions;
end

return {
    new = tsukuyomi_new,
    remove = tsukuyomi_remove,
    read = tsukuyomi_read,
    setCmd = tsukuyomi_cmd_set,
    unsetCmd = tsukuyomi_cmd_unset
};
