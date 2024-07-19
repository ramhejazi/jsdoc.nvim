local M = {}
local ls = require('luasnip')
local s = ls.snippet
-- local sn = ls.snippet_node
-- local isn = ls.indent_snippet_node
local t = ls.text_node
local i = ls.insert_node

M['return_statement'] = function(data, snippet, index)
    local ret = ' * @returns'
    local type = data.type
    -- print('index is ' .. index)
    if type then
        ret = ret .. ' {' .. type .. '} - '
        table.insert(snippet, t({ '', ret }))
        index = index + 1
        table.insert(snippet, i(index, 'desc'))
    else
        table.insert(snippet, t({ '', ret }))
    end
    return index
end

M['method_definition'] = function(data)
    return M['function_declaration'](data)
end

M['expression_statement'] = function(data)
    return M['default']()
    -- return M['function_declaration'](data)
end

M['function_declaration'] = function(data)
    local _start = t { '/**' }
    local _end = t { '', ' */' }
    local snippet = { _start }
    local index = 1
    -- Log(data)
    table.insert(snippet, t { '', ' * ' })
    table.insert(snippet, i(index, "description"))
    if data.meta.async then
        table.insert(snippet, t { '', ' * @async' })
    end
    if data.meta.name then
        local first_char = data.meta.name:sub(1, 1)
        if first_char:upper() == first_char then
            table.insert(snippet, t { '', ' * @constructor' })
        end
    end
    if data.meta.arguments then
        index = M['function_arguments'](data.meta.arguments, snippet, index)
    end
    if data.meta.return_statement then
        index = M['return_statement'](data.meta.return_statement, snippet, index)
    end
    table.insert(snippet, _end)
    return s('__jsdoc', snippet)
end

M['default'] = function()
    return s('__jsdoc', { t { '/** ' }, i(1, ''), t { " */" }, i(0) })
end

M['function_arguments'] = function(arguments, snippet, index)
    for _, arg in ipairs(arguments) do
        -- Log(arg)
        if arg.properties then
            table.insert(snippet, t({ '', ' * @param {' .. arg.type .. '} options - ' }))
            index = index + 1;
            table.insert(snippet, i(index, 'desc'))
            for _, prop in ipairs(arg.properties) do
                table.insert(snippet,
                    t({ '', ' * @param {' .. (prop.type or 'any') .. '} options.' .. prop.name .. ' - ' }))
                index = index + 1;
                table.insert(snippet, i(index, 'desc'))
                -- Log(prop)
            end
        else
            local start = ' * @param {' .. (arg.type or 'any') .. '} '
            local name = (arg.name or '')
            if arg.value then
                name = name .. '=' .. arg.value
            end
            table.insert(snippet, t({ '', start .. name .. ' - ' }))
            index = index + 1;
            table.insert(snippet, i(index, 'desc'))
        end
        -- print(arg.type)
    end
    return index
end

return M;
