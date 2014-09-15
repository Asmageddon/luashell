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

local shell_template_data = {
    ui = {
        prompt  = "In [%i]: ",
        prompt2 = function(self) return self:str_rpad("...: ", #self:process_format(self.ui.prompt), " ") end,
        input   = function(self) return self.ui.prompt .. "%input\n" end, -- Usually unused
        output  = "Out[%i]: %output\n",
        error   = "Err[%i]: %error\n",
        footer  = "\n"
    },
    config = {
        replacements = {
            ["%output"] = function(self)
                local r = "";
                for i, v in ipairs(self.state.history.last_output) do
                    r = r .. __str(v)
                    if i < #self.state.history.last_output then
                        r = r  .. ",\t"
                    end
                end
                return r
            end,
            ["%input"] = function(self) return __str(self.state.history.last_input) end,
            ["%error"] = function(self) return __str(self.state.history.last_error) end,
            ["%result"] = function(self) return __str(self.state.history.last_result) end,

            ["%i"] = function(self) return __str(self.state.history.i) end,
        },
        pairs = {
            -- ' and " are single-line only
            ["[["] = "]]",
            ["("] = ")",
            ["["] = "]",
            ["{"] = "}",
        },
        commands = {
            ["quit"] = function(self) self.state.running = false end
        }
    },
    state = {
        running = false,
        history = {
            last_input = "",
            last_output = {},
            last_error = "",
            last_result = "",
            i = 1
        },
        io = {
            input = "",
            output = ""
        }
    }
}

local shell_methods = {}

-- Shell utility methods
function shell_methods.escape(self, text)
    local src = string.gsub("^$()%.[]*+-?)", ".", "%%%1")
    return text:gsub("["..src.."]","%%%1")
end

function shell_methods.process_format(self, template)
    if type(template) == "function" then
        template = template(self)
    end

    local result = template
    for a, b in pairs(self.config.replacements) do
        b = b(self)
        a, b = self:escape(a), b
        result = result:gsub(a, b)
    end
    return result
end

function shell_methods.check_pairs(self, text)
    local text = string.gsub(text, [['([^']*)']], "") -- Get rid of strings in '' quotes
    local text = string.gsub(text, [["([^"]*)"]], "") -- Get rid of strings in "" quotes
    local text = string.gsub(text, "%[%[.-%]%]", "") -- Get rid of strings in [[ ]] quotes

    for a, b in pairs(self.config.pairs) do
        a, b = self:escape(a), self:escape(b)
        if (a == b) then
            local _, count = string.gsub(text, a, "")
            return (count %2) == 0
        else
            local _, count1 = string.gsub(text, a, "")
            local _, count2 = string.gsub(text, b, "")
            if count1 > count2 then return false end
        end
    end

    return true
end

function shell_methods.str_rpad(self, __str, len, char)
    char = char or ' '
    return string.rep(char, len - #__str) .. __str
end

-- Shell's interface methods, for sending and receiving data to/from it
function shell_methods:send(text)
    self.state.io.input = self.state.io.input .. text
    if self:check_pairs(self.state.io.input) then
        self:execute(self.state.io.input)
        self.state.history.last_input = self.state.io.input
        self.state.io.input = ""
        self.state.history.i = self.state.history.i + 1
        return true
    else
        self.state.io.input = self.state.io.input .. "\n"
        return false
    end
end

function shell_methods:receive()
    local out = self.state.io.output
    self.state.io.output = ""
    return out
end

-- Shell's output methods, for writing output
function shell_methods:write(...)
    local args = {...}
    for _, text in ipairs(args) do
        self.state.io.output = self.state.io.output .. text
    end
end

function shell_methods:print(...)
    local args = {...}
    for i, text in ipairs(args) do
        self:write(text)
        if i ~= #args then self:write("\t") end
    end
    self:write("\n")
end

function shell_methods:writef(...)
    local args = {...}
    for _, text in ipairs(args) do
        self:write(self:process_format(text))
    end
end

-- Shell's most important method, for executing code
function shell_methods:execute(text, print_input)
    print_input = print_input or false
    if print_input then
        self:writef(self.ui.input)
    end

    -- Attempt to load the code as a statement and grab its return value
    local code, err = loadstring("return " .. text)

    -- It's not a statement and cannot be treated as one, load directly
    if err then
        code = loadstring(text)
    end

    local result = {xpcall(code,
        function(error)
            self.state.history.last_output = {}
            self.state.history.last_result = error
            self.state.history.last_error = error
            self:writef(self.ui.error, self.ui.footer)
        end
    )}

    local success = result[1]
    table.remove(result, 1)

    if success then
        self.state.history.last_output = result
        self.state.history.last_result = result
        self.state.history.last_error = ""
        if #result > 0 then
            self:writef(self.ui.output)
        end
        self:writef(self.ui.footer)
    end

    return result
end

-- Template interface, containing default methods for all interfaces
local template_interface = {
    init = function(self, shell)
        self.shell = shell
    end,

    prompt_quit = function(self)
        while true do
            self:write("\n")
            local input = self:read("Do you really want to quit ([y]/n)? ")
            if input == "" or input == "y" or input == "yes" then
                return true
            elseif input == "n" or input == "no" then
                return false
            end
            -- if input is another string, or nil, continue
        end
    end,

    stop = function(self) end,

    read = function(self, prompt)
        local status, result = pcall(self._read, self, prompt)
        if status then
            return result -- no error, all fine, alles gut
        else
            -- TODO, we need to handle the potential interrupt. This needs a signal handling library.
            return nil -- return nil instead of crashing
        end
    end,

    write = function(self, ...)
        local args, text = {...}, ""
        for _, substring in ipairs(args) do
            text = text .. substring
        end
        self.shell.state.io.output = self.shell.state.io.output .. text
        self:flush()
    end,

    on_exec = function(self) end,

    run = function(self, shell)
        self:init(shell)

        self.shell.state.running = true
        while self.shell.state.running do
            local input = self:read(self.shell.ui.prompt)

            if input == nil then
                if self:prompt_quit() then
                    self.shell.state.running = false
                end
            else
                local cmd = self.shell.config.commands[input]
                if cmd then
                    cmd(self.shell)
                    break
                end

                while not self.shell:send(input) do
                    input = self:read(self.shell.ui.prompt2)
                    --input = input .. "\n" .. more_input
                end
                self:on_exec()
                self:flush()
            end
        end

        self:stop()
    end
}

-- CLI interfaces - simple io.read/io.write one, and a more sophisticated readline one
local cli_interface = {
    flush = function(self)
        local out = self.shell:receive()
        io.write(out)
    end,

    _read = function(self, prompt)
        self.shell:writef(prompt)
        self:write()
        return io.read()
    end
}

local readline_interface = {
    init = function(self, shell)
        self.shell = shell
        self.RL = require "readline"
        self.RL.set_options{
            keeplines=1000,
            histfile='~/.luashell_hist',
            completion=false,
            auto_add=false,
        }
    end,

    stop = function(self)
        self.RL.save_history()
    end,

    on_exec = function(self)
        self.RL.add_history(self.shell.state.history.last_input)
    end,

    flush = function(self)
        local out = self.shell:receive()
        io.write(out)
    end,

    _read = function(self, prompt)
        prompt = self.shell:process_format(prompt)
        return self.RL.readline(prompt)
    end
}

-- Utility functions for pretty printing
local function table_to_string(obj, pretty_mode, expand_tables, _indent_level)
    pretty_mode = pretty_mode or false
    expand_tables = expand_tables or false

    --Handle indentation levels
    local indent_level = _indent_level or 1
    local indent = ""
    local prev_indent = ""

    for i=1,indent_level do indent = indent .. "    " end
    for i=1,indent_level-1 do prev_indent = prev_indent .. "    "  end
    --Done

    local result = "{"
    if pretty_mode then result = result .. "\n"; end

    local number_mode, number_mode_key = false, 1
    for k, v in pairs(obj) do
        if k == number_mode_key then
            number_mode, number_mode_key = true , number_mode_key + 1
        else
            number_mode, number_mode_key = false, nil
        end

        if pretty_mode then result = result .. indent end
        if not number_mode then
            result = result .. tostring(k) .. " = "
        end

        if type(v) == "table" then
            if v == obj then
                result = result .. "self"
            elseif expand_tables then
                result = result .. table_to_string(v, pretty_mode, expand_tables, indent_level + 1)
            else
                result = result .. tostring(v)
            end
        else
            result = result .. __str(v)
        end

        result = result .. ", "
        if pretty_mode then result = result .. "\n" end
    end
    result = result .. prev_indent .. "}"

    return result
end

function __str(obj, pretty_mode)
    pretty_mode = pretty_mode or false
    local obj_type = type(obj)
    if obj_type == "number" then
        return tostring(obj)
    elseif obj_type == "string" then
        return '"' .. obj .. '"'
    elseif obj_type == "function" then
        return tostring(obj)
    elseif obj_type == "table" then
        return table_to_string(obj, pretty_mode)
    elseif obj_type == "nil" then
        return "nil"
    elseif obj_type == "boolean" then
        return tostring(obj)
    else
        return tostring(obj) or "userdata/unknown"
    end
end

str = __str


local function deep_copy(t, dest, aType)
    local t = t or {}
    local r = dest or {}
    for k,v in pairs(t) do
        if aType and type(v)==aType then
            r[k] = v
        elseif not aType then
            if type(v) == 'table' and k ~= "__index" then
                r[k] = deep_copy(v)
            else
                r[k] = v
            end
        end
    end
    return r
end

function shell()
    local s = {}
    deep_copy(shell_template_data, s)
    deep_copy(shell_methods, s)
    setmetatable(s, shell_mt)

    return s
end

function interface(name_or_table)
    name_or_table = name_or_table or "best_cli"
    local chosen_interface
    if type(name_or_table) == "table" then
        chosen_interface = name_or_table
    elseif name_or_table == "best_cli" then
        local state, result = pcall(require, "readline")
        if state == true then
            chosen_interface = readline_interface
        else
            print("Module 'readline.lua' not found, defaulting to standard CLI shell")
            chosen_interface = cli_interface
        end
    elseif name_or_table == "cli" then
        chosen_interface = cli_interface
    elseif name_or_table == "readline" then
        chosen_interface = readline_interface
    end

    local interface = {}

    deep_copy(template_interface, interface)
    deep_copy(chosen_interface, interface)

    return interface
end

function run()
    local s = shell()
    local i = interface()
    __interface = i
    __shell = s
    i:run(s)
end

run()