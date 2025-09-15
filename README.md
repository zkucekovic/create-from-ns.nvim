# create-from-ns.nvim

A small Neovim plugin to **create/open PHP files based on namespaces** and generate boilerplate using [LuaSnip](https://github.com/L3MON4D3/LuaSnip).

---

## Features

- Reads `composer.json` autoload/autoload-dev PSR-4 mappings.
- Resolves namespace → file path.
- Opens file if it exists.
- If missing, creates the file and expands a LuaSnip snippet based on filename patterns.
- Fully configurable via setup.

---

## Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "zkucekovic/create-from-ns.nvim",
  dependencies = { "L3MON4D3/LuaSnip" },
  config = function()
    require("create_from_ns").setup({
      rules = {
        { pattern = "Interface", trigger = "iface" },
        { pattern = "Trait", trigger = "trait" },
        { pattern = ".*", trigger = "class" },
      }
    })
  end
}

## Usage
1. Place cursor on a fully qualified namespace (for example
`\Intellex\Storage\Entity\Embedding\EmbeddingVectorInterface)`

2. Run:

`:CreateFromNS`
        
If file exists it will be opened.
If it does not exist it will be created and a LuaSnip snippet will be expanded based on the configured rules.
