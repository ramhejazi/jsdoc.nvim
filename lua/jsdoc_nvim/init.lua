local M = {}
local ts = require('jsdoc_nvim.ts')
local providers = require('jsdoc_nvim.providers')
local ts_utils = require 'nvim-treesitter.ts_utils'
local ls = require('luasnip')

--- Detect structure, generate luasnip and expand it
---@param options table
M.generate = function(options)
    local data = ts.get_data() or {};
    if data then
        local ln = data.line_number
        local indentation = data.indentation
        local type = data.type
        local snippet;
        if providers[type] ~= nil then
            snippet = providers[type](data)
        end
        if snippet then
            vim.api.nvim_buf_set_lines(0, ln, ln, false, { indentation })
            ls.snip_expand(snippet, { pos = { ln, #indentation }, indent = true });
        end
    end
end

M.is_context_javascript = function()
    -- use ts_utils instead of vim.treesitter.get_node as it also works for
    -- injected languages
    local ok, node = pcall(function() return ts_utils.get_node_at_cursor(0) end)
    if not ok then return print('could not call get_node') end
    if not node then return false end

    local line, col = node:start()
    local _, _, tree = ts_utils.get_root_for_position(line, col)
    if tree == nil or tree:lang() ~= 'javascript' then
        -- Log('Lang is not JavaScript. it is ' .. tree:lang())
        return false
    end
    return true;
end

M.setup = function(options)
    vim.api.nvim_create_user_command('JSDoc', function(option)
        M.generate(option)
    end, { nargs = 1 })
end

M.deactivate = function()
    local files = { 'jsdoc_nvim.utils', 'jsdoc_nvim.providers', 'jsdoc_nvim.ts', 'jsdoc_nvim' }
    for _, file in ipairs(files) do
        pcall(function()
            package.loaded[file] = nil
        end)
    end
end

return M;
