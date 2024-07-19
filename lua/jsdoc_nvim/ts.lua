local ts_utils = require 'nvim-treesitter.ts_utils'
local target_types = {
    'assignment_expression', 'expression_statement', 'method_definition', 'pair',
    'function_definition', 'function_declaration' }


-- Define the function name earlier so lua won't complain about non-existent fn
-- local find_return;

local M = {}

--- Get ts node text
---@param node table - TSNode
---@return string
M.get_node_text = function(node, bufnr)
    return vim.treesitter.get_node_text(node, 0)
end


--- Get children of a node as a table
---@param node table - TSNode
---@return table
M.get_children = function(node)
    local items = {}
    for child in node:iter_children() do
        local ctype = child:type()
        if child:named() then
            items[#items + 1] = {
                type = ctype,
                item = child
            }
        end
    end
    return items
end

---
---@param node table
---@return table
local __normalize_object_assignment_pattern = function(node)
    local children = M.get_children(node)
    local _prop = children[1];
    local prop_name = M.get_node_text(_prop.item)
    local _value = children[2];
    local value_type = _value.type
    local value = M.get_node_text(_value.item)
    if value_type == 'false' or value_type == 'true' then
        value_type = 'boolean'
    end
    return { name = prop_name, type = value_type, value = value }
end

--- get destructured object parameter details
-- used for creating param comments
M.get_object_details = function(node)
    local props = M.get_children(node);
    local ret = {}
    for _, prop in ipairs(props) do
        local item = prop.item
        local type = item:type()
        if type == 'shorthand_property_identifier_pattern' then
            table.insert(ret, { name = M.get_node_text(item) })
        elseif type == 'object_assignment_pattern' then
            local normalized = __normalize_object_assignment_pattern(item)
            table.insert(ret, normalized)
        else
        end
    end
    return ret
end

--- get paramters of the function definition node
---@param  node table
---@return table
M.get_fn_params = function(node)
    local params = M.get_children(node)
    local ret = {}
    for _, param in ipairs(params) do
        local item = param.item
        local type = item:type()
        -- destructured object params
        -- exmaple_fn({ foo = 3, bar = {} })
        if type == 'object_pattern' then
            local def = M.get_object_details(item)
            table.insert(ret, { type = 'object', properties = def })

            -- simple identifier params
            -- exmaple_fn(foo)
        elseif type == 'identifier' then
            local name = M.get_node_text(item)
            table.insert(ret, { name = name })

            -- simple identifier params
            -- exmaple_fn(foo = 3)
        elseif type == 'assignment_pattern' then
            local normalized = __normalize_object_assignment_pattern(item)
            table.insert(ret, normalized)
        end
    end
    return ret
end


M.get_children_table = function(node)
    local items = {}
    for child in node:iter_children() do
        local ctype = child:type()
        if child:named() then
            items[ctype] = child
        elseif ctype == 'async' then
            items['async'] = true
        end
    end
    return items
end

M.get_fn_details     = function(node)
    local items = M.get_children_table(node)
    local ret = {}
    -- Log(items)
    if items['async'] then
        ret['async'] = true
    end
    if items['identifier'] then
        ret['name'] = M.get_node_text(items['identifier'])
    end
    if items['formal_parameters'] then
        ret['arguments'] = M.get_fn_params(items['formal_parameters'])
    end
    if items['statement_block'] then
        local return_statement = M.find_return(items['statement_block'])
        if return_statement then
            ret['return_statement'] = return_statement
        end
    end
    return ret
end

M.get_closest_parent = function(node)
    local parent = node
    local node_row = node:start()
    while node do
        node = node:parent()
        if not node then return parent end
        local parent_row = node:start()
        if node_row ~= parent_row then
            return parent
        end
        if node:type() == 'program' then return parent end
        if node then parent = node end
    end

    return parent
end

M.find_return        = function(node)
    local return_statement
    local return_type = 'any'
    for child in node:iter_children() do
        local ctype = child:type()

        if ctype == 'return_statement' then
            return_statement = child;
            break
        end
        local parent = M.get_closest_parent(child);
        if parent and parent:type() == 'return_statement' then
            return_statement = child;
            break
        end
    end
    if return_statement then
        for child in return_statement:iter_children() do
            if child:type() ~= 'return' and child:named() then
                if vim.tbl_contains({ 'string', 'number' }, child:type()) then
                    return_type = child:type()
                else
                    -- print('unknown return type ', child:type())
                end
            end
        end
        return { type = return_type }
    end
end


--- Get whitespace of the current line and use it for
--- indentation of the snippet. It returns "" when the line is empty
---@param line_number number
---@return string
local get_indentation = function(line_number)
    local ret = vim.api.nvim_buf_get_lines(0, line_number, line_number + 1, false)
    if #ret == 1 then
        local text = ret[1]
        local ws = text:match("^(%s+)")
        if ws then
            return ws
        end
    end
    return ""
end

---
---@param node
---@return
local detect = function(node)
    local type = node:type()
    local line_number = node:start()
    local indentation = get_indentation(line_number)
    local ret = { subtype = type, line_number = line_number, indentation = indentation }
    if type == 'function_declaration' or type == 'method_definition' then
        ret['type'] = 'function_declaration'
        ret['meta'] = M.get_fn_details(node)
        -- example `module.exports = function(...) {}`
    elseif type == 'expression_statement' then
        local items = M.get_children(node)
        if #items == 1 and items[1].type == 'assignment_expression' then
            local children = M.get_children(items[1].item)
            -- print('assignment_expression detected')
            local ftypes = { 'function_expression', 'arrow_function' }
            if #children == 2 and children[1].type == 'member_expression' and vim.tbl_contains(ftypes, children[2].type) then
                -- print('function assignment detected')
                local fn = children[2].item
                ret['type'] = 'function_declaration'
                ret['meta'] = M.get_fn_details(fn)
            else
                ret['type'] = 'expression_statement'
            end
        else
            ret['type'] = 'expression_statement'
        end
    elseif type == 'pair' then
        local children = M.get_children(node)
        local identifier_node = children[1].item;
        local identifier_name = M.get_node_text(identifier_node)
        local value = children[2].item;
        if value and vim.tbl_contains({ "function_expression", "arrow_function" }, value:type()) then
            ret['type'] = 'function_declaration'
            ret['meta'] = M.get_fn_details(value)
            -- print('identifier_name: ' .. identifier_name)
        end
        -- print('type: ' .. value:type())
    elseif type ~= 'comment' then
        ret['type'] = 'default'
    end

    return ret
end

M.get_data = function()
    -- local bufnr = vim.api.nvim_get_current_buf();
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
    node = M.get_closest_parent(node)
    if not node then return end

    -- print('parent_type ' .. vim.inspect(node:type()))
    if node:type() == 'ERROR' then
        print("Possible JavaScript syntax error detected by treesitter.")
        return
    end
    -- If the target node matches any item extract more data
    -- if vim.tbl_contains(target_types, node:type()) then
    return detect(node)
    -- end
end

return M
