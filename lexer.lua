--[[

    lexer.lua
    Created by Masatoshi Teruya on 14/04/28.
    
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
-- patterns
local PAT_SYMBOL = '[-+*/^.<>=~"\'(){}%%%[%],:;#%s]';
local PAT_NONIDENT = '[^%w_]';
local PAT_TRIM = '^[%s]*(.*[^%s])[%s]*$';
-- types
local T_EPAIR = -1;
local T_UNKNOWN = 0;
local T_SPACE = 1;
local T_LITERAL = 2;
local T_LABEL = 3;
local T_VAR = 4;
local T_VLIST = 5;
local T_KEYWORD = 6;
local T_OPERATOR = 7;

-- set keywords
local KEYWORD = {};
do
    local i,v;
    
    for i, v in ipairs({
        'break', 'goto', 'do', 'end', 'while', 'repeat', 'until', 'for', 'in', 
        'if', 'elseif', 'else', 'then', 'function', 'return', 'local', 'true', 
        'false', 'nil'
    }) do
        KEYWORD[v] = T_KEYWORD;
    end
end

-- symbol type table
local SYMBOL_TYPE = {
    [' '] = T_SPACE,
    ['::'] = T_LABEL,
    [','] = T_VLIST
};
do
    local i,v;

    -- literal
    for i, v in ipairs({
        '"', '\'', '[[', ']]'
    }) do
        SYMBOL_TYPE[v] = T_LITERAL;
    end
    -- operator
    for i, v in ipairs({
        '+', '-', '*', '/', '%', '^', ',', ';', '.', '..', '[', ']', '(', ')', 
        '{', '}', '<', '<=', '>', '>=', '=', '==', '~=', '#', ':', 'and', 'or', 
        'not'
    }) do
        SYMBOL_TYPE[v] = T_OPERATOR;
    end
end


-- symbol look-ahead table
local SYMBOL_LA = {};
do
    local i,v;
    
    for i, v in ipairs({
        '+', '-', '*', '/', '%', '^', ',', ';', '(', ')', '{', '}', '"', '\'', 
        '#'
    }) do
        SYMBOL_LA[v] = 0;
    end
    
    for i, v in ipairs({
        '.', '[', ']', '<', '>', '=', '~', ':'
    }) do
        SYMBOL_LA[v] = 1;
    end
end


local function trim( str )
    return str:match( PAT_TRIM );
end


local function handleEnclosureToken( state, head, tail, token )
    if token ~= ']]' then
        local category = SYMBOL_TYPE[token];
        local lhead, ltail, pat;
        
        if token == '[[' then
            pat = ']]';
        else
            pat = token;
        end
        
        lhead, ltail = state.expr:find( pat, tail + 1 );
        -- found close symbol
        if lhead then
            -- substruct literal
            token = state.expr:sub( head, ltail );
            -- update cursor
            state.cur = ltail + 1;
            
            return head, ltail, category, token;
        end
    end
    
    state.error = T_EPAIR;
    return head, tail, T_EPAIR, token;
end


local function handleSymToken( state, head, tail, token )
    local category = token == '~' and T_OPERATOR or SYMBOL_TYPE[token];
    
    if not category then
        category = T_UNKNOWN;
    elseif category == T_LITERAL then
        return handleEnclosureToken( state, head, tail, token );
    elseif category == T_OPERATOR then
        local len = SYMBOL_LA[token];
        
        -- check next char
        if len > 0 then
            local chk = state.expr:sub( head, head + len );
            local t = SYMBOL_TYPE[chk];
            
            if t == T_OPERATOR then
                token = chk;
                tail = head + len;
            elseif t == T_LITERAL or t == T_LABEL then
                token = chk;
                tail = head + len;
                return handleEnclosureToken( state, head, tail, token );
            end
        end
    end
    -- update cursor
    state.cur = tail + 1;
    
    return head, tail, category, token;
end


local function handleNameToken( state, head, tail, token )
    local shead, stail = token:find( PAT_NONIDENT );
    local category;
    
    -- found unknown symbol
    if shead then
        category = T_UNKNOWN;
        if shead == 1 then
            token = token:sub( shead, stail );
            tail = head;
        else
            token = token:sub( 1, shead - 1 );
            tail = tail - shead;
        end
    elseif KEYWORD[token] then
        category = T_KEYWORD;
    else
        category = T_VAR;
    end
    
    -- update cursor
    state.cur = tail + 1;
    
    return head, tail, category, token;
end


local function nextToken( state )
    local head, tail, token, handle;
    
    if state.error or state.cur >= state.len then
        return head, tail;
    end
    
    -- lookup symbol
    head, tail = state.expr:find( PAT_SYMBOL, state.cur );
    
    -- found symbol
    if head then
        -- substract symbol token
        if state.cur == head then
            token = state.expr:sub( head, tail );
            handle = handleSymToken;
        -- substract left token
        else
            token = trim( state.expr:sub( state.cur, head - 1 ) );
            tail = head - 1;
            head = state.cur;
            handle = handleNameToken;
        end
    -- substract remain
    else
        head = state.cur;
        tail = state.len;
        token = trim( state.expr:sub( head ) );
        handle = handleNameToken;
    end
    
    return handle( state, head, tail, token );
end


local function scan( expr )
    return nextToken, {
        iden = false,
        expr = expr,
        len = #expr + 1,
        cur = 1,
        head = 0,
        tail = 0
    }, 1;
end


return {
    scan = scan,
    -- types
    T_EPAIR = T_EPAIR,
    T_UNKNOWN = T_UNKNOWN,
    T_SPACE = T_SPACE,
    T_LITERAL = T_LITERAL,
    T_LABEL = T_LABEL,
    T_VAR = T_VAR,
    T_VLIST = T_VLIST,
    T_KEYWORD = T_KEYWORD,
    T_OPERATOR = T_OPERATOR
};
