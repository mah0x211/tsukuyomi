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
local PAT_NUMBER = '%d+';
local PAT_TRIM = '^[%s]*(.*[^%s])[%s]*$';
-- types
local T_EPAIR = -1;
local T_UNKNOWN = 0;
local T_SPACE = 1;
local T_LITERAL = 2;
local T_LABEL = 3;
local T_VAR = 4;
local T_MEMBER = 5;
local T_VLIST = 6;
local T_KEYWORD = 7;
local T_OPERATOR = 8;
local T_NUMBER = 9;
local T_BRACKET_OPEN = 10;
local T_BRACKET_CLOSE = 11;
local T_PAREN_OPEN = 12;
local T_PAREN_CLOSE = 13;
local T_CURLY_OPEN = 14;
local T_CURLY_CLOSE = 15;

-- set keywords
local KEYWORD = {};
do
    for _, v in ipairs({
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
    ['.'] = T_MEMBER,
    [':'] = T_MEMBER,
    [','] = T_VLIST,
    ['['] = T_BRACKET_OPEN,
    [']'] = T_BRACKET_CLOSE,
    ['('] = T_PAREN_OPEN,
    [')'] = T_PAREN_CLOSE,
    ['{'] = T_CURLY_OPEN,
    ['}'] = T_CURLY_CLOSE
};
do
    -- literal
    for _, v in ipairs({
        '"', '\'', '[[', ']]', '[='
    }) do
        SYMBOL_TYPE[v] = T_LITERAL;
    end
    -- operator
    for _, v in ipairs({
        '+', '-', '*', '/', '%', '^', ';', '..', '<', '<=', 
        '>', '>=', '=', '==', '~=', '#', 'and', 'or', 'not'
    }) do
        SYMBOL_TYPE[v] = T_OPERATOR;
    end
end


-- symbol look-ahead table
local SYMBOL_LA = {};
do
    for _, v in ipairs({
        '+', '-', '*', '/', '%', '^', ',', ';', '(', ')', '{', '}', '"', '\'', 
        '#', ']'
    }) do
        SYMBOL_LA[v] = 0;
    end
    
    for _, v in ipairs({
        '.', '[', '<', '>', '=', '~', ':'
    }) do
        SYMBOL_LA[v] = 1;
    end
end


local function trim( str )
    return str:match( PAT_TRIM );
end

local function handleBracketLiteralToken( state, head, tail, token )
    local category = SYMBOL_TYPE[token];
    local lhead, ltail, pat;
    
    if token == '[[' then
        pat = ']]';
    else
        -- find end of open bracket
        lhead, ltail = state.expr:find( '^%[=+%[', head );
        
        if not lhead then
            state.error = T_EPAIR;
            return head, tail, T_EPAIR, token;
        end
        
        -- update tail index
        tail = ltail;
        -- create close bracket pattern
        pat = ']' .. state.expr:sub( lhead + 1, ltail - 1 ) .. ']';
    end
    
    lhead = tail;
    while( lhead ) do
        lhead, ltail = state.expr:find( pat, lhead + 1, true );
        -- found close symbol and not escape sequence: [\] at front
        if lhead and state.expr:byte( lhead - 1 ) ~= 0x5C then
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


local function handleEnclosureToken( state, head, tail, token )
    if token ~= ']]' then
        local category = SYMBOL_TYPE[token];
        local pat = token;
        local lhead = tail;
        local ltail;
        
        while( lhead ) do
            lhead, ltail = state.expr:find( pat, lhead + 1, true );
            -- found close symbol and not escape sequence: [\] at front
            if lhead and state.expr:byte( lhead - 1 ) ~= 0x5C then
                -- substruct literal
                token = state.expr:sub( head, ltail );
                -- update cursor
                state.cur = ltail + 1;
                
                return head, ltail, category, token;
            end
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
    elseif category == T_OPERATOR or category == T_MEMBER or 
           category == T_BRACKET_OPEN or category == T_BRACKET_CLOSE then
        local len = SYMBOL_LA[token];
        
        -- check next char
        if len > 0 then
            local chk = state.expr:sub( head, head + len );
            local t = SYMBOL_TYPE[chk];
            
            if t == T_OPERATOR then
                token = chk;
                tail = head + len;
                category = t;
            elseif t == T_LITERAL or t == T_LABEL then
                token = chk;
                tail = head + len;
                
                -- bracket literal
                if token:byte( 1 ) == 0x5B then
                    return handleBracketLiteralToken( state, head, tail, token );
                end
                
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
    else
        category = KEYWORD[token] or SYMBOL_TYPE[token];
        
        if not category then
            if token:find( PAT_NUMBER ) then
                category = T_NUMBER;
            else
                category = T_VAR;
            end
        end
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
    T_MEMBER = T_MEMBER,
    T_VLIST = T_VLIST,
    T_KEYWORD = T_KEYWORD,
    T_OPERATOR = T_OPERATOR,
    T_NUMBER = T_NUMBER,
    T_BRACKET_OPEN = T_BRACKET_OPEN,
    T_BRACKET_CLOSE = T_BRACKET_CLOSE,
    T_PAREN_OPEN = T_PAREN_OPEN,
    T_PAREN_CLOSE = T_PAREN_CLOSE,
    T_CURLY_OPEN = T_CURLY_OPEN,
    T_CURLY_CLOSE = T_CURLY_CLOSE
};
