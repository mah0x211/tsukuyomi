--[[

    generator.lua
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

-- modules
local util = require('util');
local lexer = require('tsukuyomi.lexer');
-- constants
local INDENT = ('%4s'):format('');

-- class
local Generator = require('halo').class.Generator;

-- analyze
local function stackPush( stack, state, t )
    local token = {
        list = {},
        len = 0
    };
    
    state.type = t;
    state = {
        token = token
    };
    stack.len = stack.len + 1;
    stack.list[stack.len] = state;
    
    return state, token;
end


local function stackPop( stack, token, t, v )
    local state = stack.len > 1 and stack.list[stack.len - 1] or nil;
    
    if not state or state.type ~= t then
        return 'unexpected symbol: ' .. v;
    else
        local tmp = '';
        
        -- merge current tokens
        table.foreach( token.list, function( _, item )
            tmp = tmp .. item.val;
        end);
        v = tmp .. v;
        
        -- append to prev token
        token = state.token;
        if token.len > 0 then
            tmp = token.list[token.len];
            if tmp.type == lexer.T_VAR then
                t = tmp.type;
                v = tmp.val .. v;
                token.len = token.len - 1;
            end
        end
        
        -- remove current stack
        stack.list[stack.len] = nil;
        stack.len = stack.len - 1;
        
        return nil, state, token, t, v;
    end
end


local PRIVATE_IDEN = {
    ['_G']          = true,
    ['_TSUKUYOMI_'] = true,
    ['_RES_']       = true,
    ['_IDX_']       = true,
    ['_DATA_']      = true,
    ['_TBLCONCAT_'] = true
};
local UNRESERVED_WORD = {
    ['in']      = true,
    ['nil']     = true,
    ['true']    = true,
    ['false']   = true
};
--TODO: should check tag context.
local function analyze( ctx, tag )
    if tag.expr then
        local token = {
            list = {},
            len = 0
        };
        local state = {
            token = token
        };
        local stack = {
            list = { state },
            len = 1
        }
        local err;
        
        for _, _, t, v in lexer.scan( tag.expr ) do
            if t == lexer.T_EPAIR then
                return ('unexpected symbol: %q'):format( v );
            elseif t == lexer.T_UNKNOWN then
                -- found data variable prefix
                -- not member fields
                if v == '$' then
                    t = lexer.T_VAR;
                    v = '_DATA_';
                else
                    return ('unexpected symbol: %q'):format( v );
                end
            elseif t == lexer.T_KEYWORD then
                if not UNRESERVED_WORD[v] then
                    return ('invalid keyword: %q'):format( v );
                end
            -- merge space
            elseif t == lexer.T_SPACE then
                t = state.type;
                v = token.list[token.len].val .. v;
                token.len = token.len - 1;
            elseif t == lexer.T_VAR then
                if state.type == lexer.T_MEMBER then
                    v = token.list[token.len].val .. v;
                    token.len = token.len - 1;
                -- private ident
                elseif PRIVATE_IDEN[v] then
                    return ('cannot access to private variable: %q'):format( v );
                -- to declare to local if identifier does not exists at environment
                elseif not ctx.env[v] then
                    ctx.localDecl[v] = true;
                end
            elseif t == lexer.T_MEMBER then
                v = token.list[token.len].val .. v;
                token.len = token.len - 1;
            elseif t == lexer.T_BRACKET_OPEN then
                state, token = stackPush( stack, state, lexer.T_BRACKET_CLOSE );
            elseif t == lexer.T_PAREN_OPEN then
                if not state.type or state.type == lexer.T_OPERATOR or 
                   state.type == lexer.T_VAR or state.type == lexer.T_PAREN_OPEN then
                    state, token = stackPush( stack, state, lexer.T_PAREN_CLOSE );
                else
                    return ('invalid syntax: %q'):format( v );
                end
            elseif t == lexer.T_BRACKET_CLOSE or t == lexer.T_PAREN_CLOSE then
                err, state, token, t, v = stackPop( stack, token, t, v );
                if err then
                    return err;
                end
            end
            
            state.prev = state.type;
            state.type = t;
            token.len = token.len + 1;
            token.list[token.len] = {
                ['type'] = t,
                val = v
            };
        end
        
        -- check stack length
        if stack.len ~= 1 then
            return ('invalid syntax: %q'):format( token.list[token.len].val );
        end
        
        return nil, token.list, token.len;
    end
    
    return ('too few arguments: %q'):format( tag.expr );
end


local function tokenConcat( token, len )
    local expr = '';
    
    for i = 1, len do
        expr = expr .. token[i].val;
    end
    
    return expr;
end


-- generate source lines of code
local function appendCode( ctx, code )
    -- ignore source code if blockBreak is true.
    if not ctx.blockBreak then
        table.insert( ctx.code, table.concat( ctx.indent ) .. code );
    end
end


local function resInsert( val )
    return '_RES_[_IDX_ + 1] = ' .. val ..
           '; _IDX_ = _IDX_ + 1;';
end


-- txt
function Generator:txt_( ctx, tag )
    appendCode( ctx, resInsert( tag.expr ) );
    
    return nil;
end

-- if
function Generator:if_( ctx, tag )
    local err, token, len = analyze( ctx, tag );
    
    if not err then
        ctx.blockState[#ctx.blockState + 1] = tag;
        appendCode( ctx, tag.name .. ' ' .. tokenConcat( token, len ) .. 
                    ' then' );
        ctx.indent[#ctx.indent + 1] = INDENT;
    end
    
    return err;
end


-- elseif
function Generator:elseif_( ctx, tag )
    local err, token, len = analyze( ctx, tag );
    
    if not err then
        ctx.indent[#ctx.indent] = nil;
        appendCode( ctx, tag.name .. ' ' .. tokenConcat( token, len ) .. 
                    ' then' );
        ctx.indent[#ctx.indent + 1] = INDENT;
    end
    
    return err;
end

-- else
function Generator:else_( ctx, tag )
    local err = tag.expr and 'invalid arguments';
    
    if not err then
        ctx.indent[#ctx.indent] = nil;
        appendCode( ctx, tag.name );
        ctx.indent[#ctx.indent + 1] = INDENT;
    end
    
    return err;
end


-- do: for, while
function Generator:do_( ctx, tag )
    local err, token, len = analyze( ctx, tag );
    
    if not err then
        ctx.blockState[#ctx.blockState + 1] = tag;
        appendCode( ctx, tag.name .. ' ' .. tokenConcat( token, len ) .. ' do' );
        ctx.indent[#ctx.indent + 1] = INDENT;
    end
    
    return err;
end


-- for
function Generator:for_( ctx, tag )
    return self:do_( ctx, tag );
end


-- while
function Generator:while_( ctx, tag )
    return self:do_( ctx, tag );
end


-- break
function Generator:break_( ctx, tag )
    local err = tag.expr and 'invalid arguments';
    
    if not err then
        appendCode( ctx, tag.name .. ';' );
        ctx.blockBreak = true;
    end
    
    return err;
end


-- end
function Generator:end_( ctx, tag )
    local err = tag.expr and 'invalid arguments';
    
    if not err then
        if #ctx.blockState < 1 then
            err = 'invalid statement';
        else
            ctx.blockState[#ctx.blockState] = nil;
            ctx.indent[#ctx.indent] = nil;
            ctx.blockBreak = false;
            appendCode( ctx, tag.name );
        end
    end
    
    return err;
end


-- goto
function Generator:goto_( ctx, tag )
    local err, token, len = analyze( ctx, tag );
    
    if not err then
        if len ~= 1 then
            err = 'invalid arguments';
        else
            appendCode( ctx, tag.name .. ' ' .. token[1].val .. ';' );
        end
    end
    
    return err;
end


-- label
function Generator:label_( ctx, tag )
    local err, token, len = analyze( ctx, tag );
    
    if not err then
        if len ~= 1 then
            err = 'invalid arguments';
        else
            appendCode( ctx, '::' .. token[1].val .. '::' );
        end
    end
    
    return err;
end


-- put
function Generator:put_( ctx, tag )
    local err, token, len = analyze( ctx, tag );
    
    if not err then
        appendCode( ctx, resInsert( '_TSUKUYOMI_:tostring( ' .. 
                    tokenConcat( token, len ) .. ' )' ) );
    end
    
    return err;
end


-- insert
function Generator:insert_( ctx, tag )
    local err, token, len = analyze( ctx, tag );
    
    if not err then
        if len ~= 1 then
            err = 'invalid arguments';
        else
            -- extract static insertion string
            local name = token[1].val:match( '^[\'"](.*)[\'"]$' );
            -- save static insertion string
            if name then
                ctx.insertions[name] = true;
            end
            
            appendCode( ctx, resInsert( 
                ('(_TSUKUYOMI_:render( %s, _DATA_, false ))')
                :format( token[1].val )
            ));
        end
    end
    
    return err;
end


-- code
function Generator:code_( ctx, tag )
    local err, token, len = analyze( ctx, tag );
    
    if not err then
        appendCode( ctx, tokenConcat( token, len ) .. ';' );
    end
    
    return err;
end


-- helper command
function Generator:helper_( ctx, tag )
    local err, token, len = analyze( ctx, tag );
    
    if not err then
        local cmd = ctx.commands[tag.cmd];
        
        if not cmd then
            err = ('helper command %q is not defined'):format( tag.cmd );
        else
            local expr = tokenConcat( token, len );
            
            -- invoke custom command and output result
            if cmd.enableOutput then
                appendCode( ctx, resInsert( 
                    ('_TSUKUYOMI_:tostring( _TSUKUYOMI_.commands[%q].fn( %s ) )')
                    :format( tag.cmd, expr )
                ));
            -- invoke custom command
            else
                appendCode( ctx, 
                    ('_TSUKUYOMI_.commands[%q]( %s );'):format( tag.cmd, expr )
                );
            end
        end
    end
    
    return err;
    
end


local TMPL = [[local function %s( _TSUKUYOMI_, _RES_, _IDX_, _DATA_, _TBLCONCAT_ )
    %s
%s
    return _TBLCONCAT_( _RES_ );
end

return %s;
]];

-- compile script
local function compile( ctx )
    local name = ('GEN%s'):format( tostring(ctx):gsub( '^table: ', '' ) );
    local localDecl, len = util.table.keys( ctx.localDecl );
    
    -- create local variables declaration
    localDecl = len > 0 and 
                ('local %s;'):format( table.concat( localDecl, ', ' ) ) or
                '';
    
    -- generate script source
    return TMPL:format( name, localDecl, table.concat( ctx.code, '\n' ), name );
end


-- read template context
function Generator:make( tags, len, env, commands )
    local ctx = {
        rawidx = 0,
        env = env,
        commands = commands,
        code = {},
        localDecl = {},
        insertions = {},
        indent = { INDENT },
        blockState = {},
        blockBreak = false,
    };
    local tag, method, err;
    
    for idx = 1, len do
        tag = tags[idx];
        
        -- no close bracket: ?>
        if not tag.tail then
            err = 'could not found closed-bracket';
            break;
        end
        
        -- get handler
        method = self[tag.name .. '_'];
        if not method then
            err = ('unknown expr: %q'):format( tag.name );
            break;
        end
        
        err = method( self, ctx, tag );
        if err then
            break;
        end
    end
    
    if not err and #ctx.blockState > 0 then
        tag = ctx.blockState[#ctx.blockState];
        err = 'end of block statement not found';
    end
    
    if err then
        return nil, nil, err, tag;
    end
    
    -- compile context
    return compile( ctx ), ctx.insertions;
end


return Generator.exports;

