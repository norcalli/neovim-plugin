local plugin = require 'neovim-plugin'(vim)

return plugin.export {
  functions = {
    no_ns = function()
      print('no n for you')
    end;
  };
  mappings = {
    ['i!'] = 'no_ns';
    -- 'in' = function(F) return F.no_ns end;
  };
  commands = {
    Butts = 'no_ns';
  };
  attach = function(bufnr)
    print('new', bufnr)
    return {
      functions = {
        no_ls = function()
          print('no l for you specifically', bufnr)
        end;
        no_ns = function()
          print('no n for you specifically', bufnr)
        end;
      };
      commands = {
        Butts = 'no_ns';
      };
      mappings = {
        -- ['il'] = 'no_ls';
        ['i!'] = 'no_ns';
        -- ['in'] = { 'no_ns', 'l' };
      };
    }
  end;
}
