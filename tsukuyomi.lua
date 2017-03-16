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
-- modules
local coNew = coroutine.create;
local coResume = coroutine.resume;
local eval = require('util').eval;
local typeof = require('util.typeof');
local Parser = require('tsukuyomi.parser');
local Generator = require('tsukuyomi.generator');
local tblconcat = table.concat;

-- private functions

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


-- generate error string
local function errstr( label, tag, msg )
    return '[' .. label .. ':line:' .. tag.lineno .. ':' .. tag.pos .. '] ' ..
            ( msg or '' ) .. ( tag.token and ' ::' .. tag.token .. '::' or '' );
end


-- generate error string with source mapping table
local function errmap( label, srcmap, err )
    -- find error position
    local idx, msg = string.match( err, ':(%d+):(.*)' );

    if idx then
        --
        -- NOTE: should subtract 2 from line-number because code generator will
        --       generate the code as below;
        --
        --         first-line: function declaration.
        --         second-line: variable declaration.
        --         and, logic code...
        --
        idx = tonumber( idx ) - 2;
        if srcmap[idx] then
            return errstr( label, srcmap[idx], msg );
        end
    end

    return err;
end


-- class
local Tsukuyomi = require('halo').class.Tsukuyomi;


Tsukuyomi:property {
    public = {
        enableSourceMap = true,
        commands = {},
        pages = {},
        status = {}
    }
};


-- create instance
function Tsukuyomi:init( enableSourceMap, env )
    -- check arguments
    if env ~= nil then
        assert(
            typeof.table( env ),
            'environment must be type of table'
        );
        self.env = env;
    else
        self.env = _G;
    end

    if enableSourceMap ~= nil then
        assert(
            typeof.boolean( enableSourceMap ),
            'enableSourceMap must be type of boolean'
        );
        self.enableSourceMap = enableSourceMap;
    end

    self.parser = Parser.new();
    self.generator = Generator.new();

    return self;
end



-- set custom user command
function Tsukuyomi:setCommand( name, fn, enableOutput )
    assert(
        type( name ) == 'string',
        'name must be type of string'
    );
    assert(
        string.len( name ) > 0,
        'name must not be empty string'
    );
    assert(
        type( fn ) == 'function',
        'fn must be type of function'
    );
    assert(
        typeof.boolean( enableOutput ),
        'enableOutput must be type of boolean'
    );

    -- set custom command
    self.commands[name] = {
        fn = fn,
        enableOutput = enableOutput
    };
end


-- unset custom user command
function Tsukuyomi:unsetCommand( name )
    self.commands[name] = nil;
end


function Tsukuyomi:setPage( label, txt, nolf )
    local tags, ntag = self.parser:parse( txt, nolf );
    local src, ins, err, tag = self.generator:make( tags, ntag, self.env, self.commands );

    -- parse text
    if not err then
        -- compile
        src, err = eval( src, self.env, '=load(tsukuyomi@' .. label .. ')' );
        -- create readable error message
        if err then
            err = errmap( label, tags, err );
        -- add page
        else
            self.pages[label] = {
                script = src(),
                srcmap = self.enableSourceMap and tags or nil
            };
        end
    else
        err = errstr( label, tag, err );
    end

    return ins, err;
end


function Tsukuyomi:unsetPage( label )
    assert(
        typeof.string( label ),
        'label must be type of string'
    );

    self.pages[label] = nil;
end


function Tsukuyomi:render( label, data, ignoreNil )
    local status = self.status;
    local success, val;

    if type( label ) ~= 'string' then
        val = ('[label must be type of string: %q]'):format( tostring(label) );
    elseif status[label] ~= nil then
        val = ('[%q: circular insertion disallowed]'):format( label );
    else
        local page = self.pages[label];

        if not page then
            val = ('[template: %q not found]'):format( label );
        else
            -- invoke script by coroutine
            local res = {};
            local co = coNew( page.script );

            -- enable ignore nil operation switch
            if ignoreNil then
                ignoreNilOps( true );
            end

            status[label] = true;
            success, val = coResume( co, self, res, 0, data or {}, tblconcat );
            status[label] = nil;

            -- disable ignore nil operation switch
            if ignoreNil then
                ignoreNilOps( false );
            end

            if not success and page.srcmap then
                val = errmap( label, page.srcmap, val );
            end
        end
    end

    return val, success;
end


function Tsukuyomi:tostring( ... )
    local res = '';
    local t;

    -- traverse table as array
    for _, v in pairs({...}) do
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


return Tsukuyomi.exports;

