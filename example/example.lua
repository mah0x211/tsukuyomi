--[[

    test.lua
    Created by Masatoshi Teruya on 13/10/19.
    
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
local tsukuyomi = require('tsukuyomi');

-- for custom command $put
local function put( ... )
    local args = {...};
    table.insert( args, ' : custom output' );
    return table.concat( args );
end

-- create template object
local function createTemplate( sandbox )
    local enableSourceMap = true;
    local tmpl = tsukuyomi.new( enableSourceMap, sandbox );
    local enableOutput = true;
    
    -- register custom command $put
    tmpl:setCommand( 'put', put, enableOutput );
    
    return tmpl;
end

-- read template file
local function readViewFile( tmpl, path )
    local fd, err = io.open( path );
    
    if fd then
        local src;
        
        src, err = fd:read('*a');
        fd:close();
        if src then
            local label = path;
            local insertions;
            
            insertions, err = tmpl:setPage( label, src, true );
            if not err then
                for path in pairs( insertions ) do
                    readViewFile( tmpl, path );
                end
            end
        end
    end
    
    if err then
        print( err );
    end
end

-- render template
local function renderTemplate( tmpl, label, data )
    local ignoreNilOperations = true;
    local res, success = tmpl:render( label, data, ignoreNilOperations );
    
    if success then
        print( res );
    else
        print( 'error: ', res );
    end
end


local tmpl = createTemplate( _G );
local viewFile = './README.md';
local data = {
    x = {
        y = {
            z = 'external data'
        }
    }
};

readViewFile( tmpl, viewFile );
renderTemplate( tmpl, viewFile, data );

