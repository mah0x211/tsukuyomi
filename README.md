# tsukuyomi

tsukuyomi is the simple template engine written in pure Lua.

## Installation

```sh
luarocks install --from=http://mah0x211.github.io/rocks/ tsukuyomi
```

or 

```sh
git clone https://github.com/mah0x211/tsukuyomi.git
cd tsukuyomi
luarocks make
```

## Dependencies

- lua-halo: https://github.com/mah0x211/lua-halo
- lua-util: https://github.com/mah0x211/lua-util

## Usage

```lua
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
            
            insertions, err = tmpl:setPage( label, src );
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
```

## Create Object

create new template object.

### tmpl = tsukuyomi.new( [enableSourceMap [, sandbox]] )

**Parameters**

- enableSourceMap: append line number of the source code to error messages. (default true)
- sandbox: sandbox table. (default _G)

**Returns**

1. tmpl: template object.


```lua
local tsukuyomi = require('tsukuyomi');
local tmpl = tsukuyomi.new();
```

## Set/Unset Template

### ins, err = tmpl:setPage( label, src [, nolf] )

compile the passed template strings and set the generated function to tmpl object.

**Parameters**

- label: label string for associate to the compiled template.
- src: source strings of template.
- nolf: eliminate a trailing line-feed of the following tags if true;  
	`if`, `elseif`, `else`, `for`, `while`, `break`, `end`, `code`

**Returns**

1. ins: table that contains argument of insertion commands.
2. err: error string.

```lua
local tsukuyomi = require('tsukuyomi');

local function readViewFile( tmpl, path )
    local fd, err = io.open( path );
    if fd then
        local src;
        
        src, err = fd:read('*a');
        fd:close();
        if src then
            local label = path;
            local insertions;
            
            insertions, err = tmpl:setPage( label, src );
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

local tmpl = tsukuyomi.new();
readViewFile( tmpl, 'README.md' );
```

### tmpl:unsetPage( label )

remove the compiled template that associated with the label argument.

**Parameters**

- label: string.

```lua
tmpl:unsetPage( 'README.md' );
```

## Set/Unset Custom Template Command

### tmpl:setCommand( name, func, enableOutput )

register custom template command (aka helper command).

**Parameters**

- name: name of custom command.
- func: custom command implementation (function).
- enableOutput: render the return value if true.

```lua
-- for custom command $put
local function put( ... )
    local args = {...};
    table.insert( args, ' : custom output' );
    return table.concat( args );
end

-- register custom command $put
tmpl:setCommand( 'put', put, true );
```

### tmpl:unsetCommand( name )

unregister custom template command.

**Parameters**

- name: name of custom command.

```lua
-- unregister custom command $put
tsukuyomi.unsetCmd( tmpl, 'put' );
```

## Render The Template.

### res, success = tmpl:render( label, data, ignoreNil )

render the template associated with label.

**Parameters**

- label: label string that associated to the compiled template.
- data: data table that associate with `$` on the template.
- ignoreNil: ignore nil operation if true.

**Returns**

1. res: rendered string, or error message.
2. success: true on success, false on failure.

```lua
local data = {
    x = {
        y = {
            z = 'external data'
        }
    }
};
local ignoreNilOperations = true;
local res, success = tmpl:render( label, data, ignoreNilOperations );

if success then
    print( res );
else
    print( 'error: ', res );
end
```

## Template Syntax And Commands.

### put

```
<?put 'Hello World' ?>
<?put 'Hello' .. 'World' ?>
<?put 'Hello', 'World' ?>
```

to be rendered as below;

```
Hello World
HelloWorld
HelloWorld
```

### code

use for write the one-liner lua code but cannot be write a control statements.

```
<?code x = 1 ?>
<?code y = { 1, 2, 3 } ?>
<?code z = table.concat( y, '-' ) ?>
```

### insert

render the template associated with label, and insert the result string.

```
<?insert 'other_template_label' ?>
```

### if-elseif-else

```
<?if x == true ?>
x is true
<?elseif x == false ?>
x is false
<?else?>
x is <?put x ?>
<?end?>
```

### for

```
<?for i = 0, 10 ?>
i is <?put i ?>
<?end?>
```

```
<?for idx, val in pairs( y ) ?>
<?put idx ?> is <?put val ?>
<?end?>
```

```
<?for idx, val in ipairs( y ) ?>
<?put idx ?> is <?put val ?>
<?end?>
```

### while

```
<?while x < 10 ?>
x is <?put x ?>
<?code x = x + 1 ?>
<?end?>
```

### break

```
<?for i = 0, 10 ?>
i is <?put i ?>

<?if i == 5 ?>
<?break?>
<?end?>
<?end?>
```

```
<?while x < 10 ?>
x is <?put x ?>
<?code x = x + 1 ?>
<?if i == 5 ?>
<?break?>
<?end?>
<?end?>
```

### `$` Prefixed Custom Template Syntax

```
<?$put 'Hello World' ?>
```

to be rendered as below;

```
Hello World : custom output
```

## Template Variables

all variables will be declared as local variable automatically except `$` prefixed variable.

```
<?code x = 1 ?>
<?code y = { 1, 2, 3 } ?>
<?code z = table.concat( y, '-' ) ?>

<?for idx, val in pairs( y ) ?>
<?put idx ?> is <?put val ?>
<?end?>
```

above code would be declare local variable  `x`, `y`, `z`, `idx` and `val` on internally.

### `$` Prefixed variable

`$` prefixed variable is reference of the external table.

```
<?put $.x.y.z ?>
```

to be rendered as below;

```
external data
```



