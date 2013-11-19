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
local sandbox = _G;
local views = tsukuyomi.new( sandbox );
local srcmap = true;
local ignoreNilOps = true;
local err, insertions, res, success;

-- read page_hello
err ,insertions = tsukuyomi.read( views, 'hello', [[
Hello <?insert "world" ?>
]], srcmap );
if err then
    error( err );
end
-- read page_world
err, insertions = tsukuyomi.read( views, 'world', [[
World!
]], srcmap );
if err then
    error( err );
end

-- render
res, success = views:recite( 'hello', ignoreNilOps, {} );
if not success then
    error( res );
else
    print( res );
end
--print( views:recite( 'world', ignoreNilOps, {} ) );
