# neovim-plugin

This is a Lua library meant to standardize the creation of Lua based plugins in Neovim.

From here on, the word `plugin` will refer to the Lua plugin that an author wants to make.

There are a few ideas that are at the core of the guarantees trying to be provided, the
common theme is that we want to *minimize surprises to the user*:

- Plugins shouldn't use the api unless the user explicitly asks them to by calling a function.
  - For one time initialization for a plugin, this is achieved by having a `setup()` function
    which will do any initialization required unrelated to key mappings, commands, and events.
  - Every other call should be encapsulated by functions exported by the plugin.
- Plugins should *ideally* not affect global state unless it's absolutely necessary.
- Neovim features like key mappings, commands, and events should not be set unless explicitly done
so by the user by applying the defaults using the `use_defaults()` function, or should be exported in such a form that the user
could introspect or apply the definitions themselves. This is to *make sure that the user always knows
what a plugin is doing*.
- Should provide compatibility across Neovim versions from 0.4 upward by providing a compatibility shim
when appropriate and using native interfaces for Lua commands, mappings, and events and for
utility functions defined on the `vim` object which are deemed important to
writing Lua plugin ergonomics (described in Utilities section).

To achieve this, mappings, commands, and events have a specification for being able to be declared as
data in the form of Lua tables, whose specifics is described below in `Syntax`

## Demonstration

Inside of `example.lua`:

```lua
-- From inside of a module of a plugin you're creating.

local plugin = require 'neovim-plugin'(vim)

local function export_this_fn()
	print("Exported function!")
end

local initialized = false

return {
  export_this_fn = export_this_fn;
  neovim_stuff = plugin.export {
    mappings = {
      nM = function() print(123) end;
      silent = true;
    };
    commands = {
      P = function() print(321) end;
      D = { function(...) print(initialized, 321, ...) end; nargs = '*'; };
      A = 'echo Hello';
    };
    setup = function()
      -- Do some stuff in here.
      initialized = true;
    end;
  }
}
```

The user can use this as:

```lua
-- This will call setup() and then apply all of the mappings and commands.
require 'example'.neovim_stuff.use_defaults()

-- Equivalently:
local plugin = require 'example'.neovim_stuff
plugin.setup()
plugin.vim.apply_mappings(plugin.mappings)
plugin.vim.apply_commands(plugin.commands)
```

The `export()` function will return a table with the keys:

- `setup()` same as input.
- `mappings` same as input, but validated and normalized.
- `commands` same as input, but validated and normalized.
- `events` same as input, but validated and normalized.
- `use_defaults()` runs setup and applies all of the mappings, commands, and events.
- `vim` a copy of the `neovim-plugin` module used by the plugin so that you can
  use the utility functions in it, like `apply_mappings()` and check its version.
  - TODO not sure on this naming. Could export all the functions flattened.

## Syntax

### Mappings

Mappings are defined in a table where the key begins with a single character describing
the mode, and the rest of the key shall be the verbatim vim key to be used, for example:

- `nK` defines a `n`ormal mode mapping for the key `K`
- `i<c-k>` defines an `i`nsert mode mapping for the key `<c-k>`
- `t df` and `t<space>df` both define a `t`erminal mode mapping for `<space>df`. In table
keys, space doesn't need to be escaped.

All of the built-in keywords are supported, such as `noremap`, `expr`, but some additional
extensions have been added such as `buffer`, which is shown in the second example.

The possible values of the key are best explained by examples:

```lua
mappings = {
  ['n ff'] = function() require 'ui'.file_fuzzy_finder(vim.loop.cwd()) end;
  ['n ff'] = '<Cmd>FuzzyFileFinder<CR>';
  ['n ff'] = ':FuzzyFileFinder<CR>';
  ['n ff'] = function() vim.cmd "FuzzyFileFinder" end;

  -- While you can use expr, with the ability to use Lua, the benefits
  -- are rather limited.

  -- Return another key stroke using the built-in expr keyword.
  ['n ff'] = { '"FuzzyFileFinder"'; expr = true; };
  -- Delete the rest of the file.
  ['n ff'] = { function() return "dG" end; expr = true; };

  -- This will return the keystrokes of the current date in insert mode, which
  -- is fairly safe...
  ['i<c-k>'] = { os.date; expr = true; noremap = true; };

  -- You can optionally specify a default option to be passed to all bindings in this dictionary.
  silent = true;
}
```

Buffer mappings are more useful when called in the buffer you care about, so you can use
the `apply_mappings` function provided instead of the global mappings you can export
using `export`.

```lua
local plugin = require 'neovim-plugin'(vim)

plugin.apply_mappings {
  -- Target the current buffer for all of the mappings.
  buffer = true;

  -- But you could override it and target a specific buffer.
	['n ff'] = { function() vim.cmd "FuzzyFileFinder" end; buffer = 123; };
}
```

## Commands

These accept all standard flags. For example `-nargs=...` would be `nargs = ...` as a keyword.

You can use `buffer = true` to target the current buffer or `buffer = N` to target buffer `N`.

```lua
commands = {
  ColorizerToggle = function() require 'colorizer'.toggle() end;
  Finder = 'FuzzyFileFinder';
  Debug = 'echo "123"';
  PrintIt = {
    nargs = '*';
    function(args)
      -- args is a single string equivalent to <q-args>
      print(args)
    end
  };
  PrintEach = {
    nargs = '*';
    function(args)
      -- args is a single string equivalent to <q-args>
      for i, arg in ipairs(vim.split(args, '%s+')) do
        print(i, arg)
      end
    end
  };
  -- Calling `:Debug 123 321` would print:
  -- "123 321" {bang = "",count = -1,range = { 1, 1, 0 },register = ""}
  Debug = {
    function(args, options)
      print(vim.inspect(args), vim.inspect(options))
    end
  };
}
```

Optionally you can use `apply_commands()`.

```lua
local plugin = require'neovim-plugin'(vim)

plugin.apply_commands(commands)
```

## Events

TODO An implementation has been created but is in process of being cleaned up
for autocommands and other events.
