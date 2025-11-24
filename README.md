# tenant-feature.nvim

Generic Neovim plugin to manage feature flags in multi-tenant Rails systems.
Not public maintained, just a personal need

## ✨ Features

- 🎯 Manage feature flags from Neovim
- 🏢 Multi-tenant support (Apartment, ActsAsTenant, etc.)
- 🔄 Compatible with multiple feature flag systems (MyCompany::Feature, Flipper, etc.)
- ⚡ Quick commands and configurable keymaps
- 🎨 Interface with `vim.ui.select`

## 📦 Installation

### Con LazyVim/Lazy.nvim

```lua
{
  "your-username/tenant-feature.nvim",
  config = function()
    require("tenant-feature").setup({
      -- Required configuration
      tenant_model = "Tenant",
      tenant_switch_template = "Apartment::Tenant.switch('%s') do; %s; end",
      enable_command = "MyCompany::Feature.enable(:%s)",
      disable_command = "MyCompany::Feature.disable(:%s)",
      check_command = "puts MyCompany::Feature.enabled?(:%s)",
    })
  end,
  lazy = false,
}
```

## ⚙️ Configuration

### Required fields

```lua
require("tenant-feature").setup({
  tenant_model = "Tenant",                -- Tenant model
  tenant_switch_template = "...",         -- Template to switch tenant
  enable_command = "...",                 -- Command to enable feature
  disable_command = "...",                -- Command to disable feature
  check_command = "...",                  -- Command to check status
})
```

### Optional fields (with defaults)

```lua
{
  rails_cmd = "bin/rails",                -- Rails command
  rails_env = "RAILS_ENV=development",    -- Environment variables
  shell = "/bin/bash",                    -- Shell to use
}
```

## 📚 Configuration examples

### Apartment + MyCompany::Feature

```lua
require("tenant-feature").setup({
  tenant_model = "Tenant",
  tenant_switch_template = "Apartment::Tenant.switch('%s') do; %s; end",
  enable_command = "MyCompany::Feature.enable(:%s)",
  disable_command = "MyCompany::Feature.disable(:%s)",
  check_command = "puts MyCompany::Feature.enabled?(:%s)",
})
```

### Flipper (sin multi-tenant)

```lua
require("tenant-feature").setup({
  tenant_model = "User",
  tenant_switch_template = "%s",
  enable_command = "Flipper.enable(:%s)",
  disable_command = "Flipper.disable(:%s)",
  check_command = "puts Flipper.enabled?(:%s)",
})
```

### ActsAsTenant + Flipper

```lua
require("tenant-feature").setup({
  tenant_model = "Account",
  tenant_switch_template = "ActsAsTenant.with_tenant(Account.find_by(name: '%s')) do; %s; end",
  enable_command = "Flipper.enable(:%s)",
  disable_command = "Flipper.disable(:%s)",
  check_command = "puts Flipper.enabled?(:%s)",
})
```

## 🎮 Usage

### Keymaps (default)

- `<leader>fe` - Enable feature for tenant
- `<leader>fd` - Disable feature for tenant
- `<leader>fc` - Check feature status

### Commands

- `:EnableFeatureForTenant` - Enable feature
- `:DisableFeatureForTenant` - Disable feature
- `:CheckFeatureForTenant` - Check status

### Workflow

1. Visually select a feature name (e.g., `viw` over "User Management")
2. Press `<leader>fe` (or your preferred command)
3. Select the tenant from the menu
4. The plugin will execute the Rails command in the tenant context

## 🛠️ Requirements

- Neovim >= 0.9
- Rails project with rbenv or Ruby version system
- Bash shell

## 📄 License

MIT License

Copyright (c) 2025 Nedzib

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
