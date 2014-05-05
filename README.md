# tsukuyomi

tsukuyomi is the simple template engine written in pure Lua.

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
    local tmpl = tsukuyomi.new( sandbox );
    local enableOutput = true;
    
    -- register custom command $put
    tsukuyomi.setCmd( tmpl, 'put', put, enableOutput );
    
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
            local enableSourceMap = true;
            local insertions;
            
            insertions, err = tsukuyomi.read( tmpl, label, src, enableSourceMap );
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

## Functions

### tmpl = tsukuyomi.new( sandbox )

create new template object.

**Parameters**

- sandbox: sandbox table. (default _G)

**Returns**

1. tmpl: template object.


```lua
local tsukuyomi = require('tsukuyomi');
local sandbox = _G;
local tmpl = tsukuyomi.new( sandbox );
```

### ins, err = tsukuyomi.read( tmpl, label, src, enableSourceMap )

compile template strings and save to passed template object.

**Parameters**

- tmpl: template object.
- label: label string for associate to the compiled template.
- src: source strings of template.
- enableSourceMap: append line number of the source code to error messages if true.

**Returns**

1. ins: table that contains argument of insertion commands.
2. err: error string.

```lua
local path = 'README.md';
local fd, err = io.open( path );
    
if fd then
    local src;
    
    src, err = fd:read('*a');
    fd:close();
    if src then
        local label = path;
        local enableSourceMap = true;
        local insertions;
        
        insertions, err = tsukuyomi.read( tmpl, label, src, enableSourceMap );
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
```


### tsukuyomi.remove( tmpl, label )

remove the compiled template that associated with the label argument.

**Parameters**

- tmpl: template object.
- label: label string.


```lua
local label = 'README.md';
tsukuyomi.remove( tmpl, label );
```


### tsukuyomi.setCmd( tmpl, name, func, enableOutput )

register custom template command.

**Parameters**

- tmpl: template object.
- name: name of custom command.
- func: custom command implementation.
- enableOutput: render the return value if true.

```lua
-- for custom command $put
local function put( ... )
    local args = {...};
    table.insert( args, ' : custom output' );
    return table.concat( args );
end

-- register custom command $put
local enableOutput = true;
tsukuyomi.setCmd( tmpl, 'put', put, enableOutput );
```


### tsukuyomi.unsetCmd( tmpl, name )

unregister custom template command.

**Parameters**

- tmpl: template object.
- name: name of custom command.

```lua
-- unregister custom command $put
tsukuyomi.unsetCmd( tmpl, 'put' );
```

## Methods

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



