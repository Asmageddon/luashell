#!/usr/bin/env lua

-- Copyright (c) 2014, Llamageddon <asmageddon@gmail.com>

-- Permission is hereby granted, free of charge, to any person obtaining a copy of
-- this software and associated documentation files (the "Software"), to deal in
-- the Software without restriction, including without limitation the rights to
-- use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
-- of the Software, and to permit persons to whom the Software is furnished to do
-- so, subject to the following conditions:
--
-- The above copyright notice and this permission notice shall be included in all
-- copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
-- OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
-- SOFTWARE.

shell = {}
shell.running = false

shell.ui = {}

shell.ui.prompt  = "In [%i]: "
shell.ui.prompt2 = function() return shell.util.str_rpad("...: ", #shell.util.process_format(shell.ui.prompt), " ") end
shell.ui.input   = shell.ui.prompt .. "%input\n" -- Usually unused
shell.ui.output  = "Out[%i]: %result\n"
shell.ui.error   = "Err[%i]: %result\n"
shell.ui.footer  = "\n"

shell.last_input = ""
shell.last_output = ""
shell.last_error = ""
shell.last_result = ""

shell.i = 1

shell.replacements = {
    ["%output"] = function() return shell.last_output end,
    ["%input"] = function() return shell.last_input end,
    ["%error"] = function() return shell.last_error end,
    ["%result"] = function() return shell.last_result end,
    ["%i"] = function() return shell.i end,
}

shell.pairs = {
    ['"'] = '"',
    ["'"] = "'",
    ["[["] = "]]",
    ["("] = ")",
    ["["] = "]",
    ["{"] = "}",
}

shell.util = {}

function shell.util.escape(text)
    local src = string.gsub("^$()%.[]*+-?)", ".", "%%%1")
    return text:gsub("["..src.."]","%%%1")
end

function shell.util.process_format(template)
    if type(template) == "function" then
        template = template()
    end

    local result = template
    for a, b in pairs(shell.replacements) do
        b = str(b())
        a, b = shell.util.escape(a), b-- shell.util.escape(b)
        --print("THINGS:", a, b)
        result = result:gsub(a, b)
    end
    return result
end

function shell.util.check_pairs(text)
    local text = string.gsub(text, [['([^']*)']], "") -- Get rid of strings in '' quotes
    local text = string.gsub(text, [["([^"]*)"]], "") -- Get rid of strings in "" quotes
    local text = string.gsub(text, "%[%[.-%]%]", "") -- Get rid of strings in [[ ]] quotes

    for a, b in pairs(shell.pairs) do
        a, b = shell.util.escape(a), shell.util.escape(b)
        local _, count1 = string.gsub(text, a, "")
        local _, count2 = string.gsub(text, b, "")
        if count1 ~= count2 then return false end
    end

    return true
end

function shell.util.str_rpad(str, len, char)
    char = char or ' '
    return string.rep(char, len - #str) .. str
end

function shell.print(...)
    local args = {...}
    for i, text in ipairs(args) do
        shell.write(text)
        if i ~= #args then shell.write("\t") end
    end
    shell.write("\n")
end

function shell.write(...)
    local args = {...}
    for _, text in ipairs(args) do
        io.write(text)
    end
end

function shell.writef(...)
    local args = {...}
    for _, text in ipairs(args) do
        shell.write(shell.util.process_format(text))
    end
end

function shell.read(prompt)
    shell.writef(prompt)
    return io.read()
end

function shell.execute(text, print_input)
    print_input = print_input or false
    if print_input then
        shell.writef(shell.ui.input)
    end

    -- Attempt to load the code as a statement and grab its return value
    local code, err = loadstring("return " .. text)

    -- It's not a statement and cannot be treated as one, load directly
    if err then
        code = loadstring(text)
    end

    local success, result = xpcall(code,
        function(error)
            shell.last_output = ""
            shell.last_result = error
            shell.last_error = error
            shell.writef(shell.ui.error, shell.ui.footer)
        end
    )

    if success then
        shell.last_output = result
        shell.last_result = result
        shell.last_error = ""
        shell.writef(shell.ui.output, shell.ui.footer)
    end
end

function shell.run()
    shell.running = true
    while shell.running == true do
        local input = shell.read(shell.ui.prompt)

        while not shell.util.check_pairs(input) do
            local more_input = shell.read(shell.ui.prompt2)
            input = input .. "\n" .. more_input
        end

        if input == "quit" then
            shell.running = false
        else
            shell.execute(input)
        end

        shell.i = shell.i + 1
    end
end

-- Utility functions for pretty printing
function dir(obj, pretty_mode, expand_tables, _indent_level)
    pretty_mode = pretty_mode or false
    expand_tables = expand_tables or false

    --Handle indentation levels
    local indent_level = _indent_level or 1
    local indent = ""
    local prev_indent = ""

    for i=1,indent_level do
        indent = indent .. "    "
    end

    for i=1,indent_level-1 do
        prev_indent = prev_indent .. "    "
    end
    --Done

    local result = "{"

    if pretty_mode then result = result .. "\n"; end

    local number_mode = false
    local number_mode_key = 1

    for k, v in pairs(obj) do
        if k == number_mode_key then
            number_mode = true
            number_mode_key = number_mode_key + 1
        else
            number_mode = false
            number_mode_key = nil
        end

        if pretty_mode then
            result = result .. indent
        end

        if not number_mode then
            result = result .. tostring(k) .. " = "
        end

        if type(v) == "table" then
            if v == obj then
                result = result .. "self"
            elseif expand_tables then
                result = result .. dir(v, pretty_mode, expand_tables, indent_level + 1)
            else
                result = result .. tostring(v)
            end
        else
            result = result .. str(v)
        end

        if pretty_mode then
            result = result .. ", \n"
        else
            result = result .. ", "
        end
    end
    result = result .. prev_indent .. "}"

    return result
end

function str(obj, pretty_mode)
    local obj_type = type(obj)
    if obj_type == "number" then
        return tostring(obj)
    elseif obj_type == "string" then
        return '"' .. obj .. '"'
    elseif obj_type == "function" then
        return tostring(obj)
    elseif obj_type == "table" then
        return dir(obj, pretty_mode)
    elseif obj_type == "nil" then
        return "nil"
    elseif obj_type == "boolean" then
        return tostring(obj)
    else
        return tostring(obj) or "userdata/unknown"
    end
end

print = shell.print
shell.run()