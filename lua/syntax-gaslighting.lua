---@class GaslightingConfig
---@field gaslighting_chance number  -- Percentage chance that a line will receive a gaslighting message
---@field min_line_length number    -- Minimum length of a trimmed line for gaslighting to apply
---@field highlight string          -- Highlight group name used for virtual text messages
---@field debounce_delay number     -- Delay in milliseconds before updating decorations
---@field auto_update boolean       -- Automatically update decorations on buffer changes
---@field merge_messages boolean    -- Merge user-defined messages with default ones
---@field filetypes_to_ignore string[] -- List of filetypes to ignore from gaslighting
---@field messages string[]         -- Array of gaslighting messages

local M = {}

--- Default configuration options
---@type GaslightingConfig
local default_config = {
    gaslighting_chance = 5,
    min_line_length = 10,
    highlight = "GaslightingUnderline",
    debounce_delay = 500,
    auto_update = true,
    merge_messages = false,
    filetypes_to_ignore = { "netrw", "NvimTree", "neo-tree", "Telescope", "qf" },
    messages = {
        "Are you sure this will pass the code quality checks? 🤔",
        "Is this line really covered by unit tests? 🧐",
        "I wouldn't commit that line without double checking... 💭",
        "Your tech lead might have questions about this one 🤔",
        "That's an... interesting way to solve this 🤯",
        "Did you really mean to write it this way? 🤔",
        "Maybe add a comment explaining why this isn't as bad as it looks? 📝",
        "Bold choice! Very... creative 💡",
        "Please. Tell me Copilot wrote this one... 🤖",
        "Totally not a memory leak... 🚽",
        "I'd be embarrassed to push this to git if I were you. 😳",
        "Would God forgive you for this? ✝️",
    },
}

---@type GaslightingConfig
local config = vim.deepcopy(default_config)

local api = vim.api
local timer = nil
local ns = api.nvim_create_namespace("syntax_gaslighting")
M.is_enabled = true

--- Convert filetype list to a set for fast lookup
local ignored_filetypes_set = {}
for _, ft in ipairs(default_config.filetypes_to_ignore) do
    ignored_filetypes_set[ft] = true
end

--- Merge user configuration with defaults
---@param user_config table
function M.setup(user_config)
    user_config = user_config or {}
    config = vim.tbl_deep_extend("force", {}, default_config, user_config)

    -- Merge messages if option is enabled and user provided messages.
    if user_config.merge_messages and user_config.messages then
        local merged = vim.deepcopy(default_config.messages)
        for _, msg in ipairs(user_config.messages) do
            table.insert(merged, msg)
        end
        config.messages = merged
    end

    -- Setup highlight group for gaslighting messages.
    vim.cmd("highlight default link " .. config.highlight .. " Comment")

    if config.auto_update then
        api.nvim_create_autocmd({ "BufEnter", "TextChanged", "TextChangedI" }, {
            callback = function() M.schedule_update() end,
        })
    end

    -- Toggle the gaslighting functionality.
    api.nvim_create_user_command("SyntaxGaslightingToggle", function()
        M.is_enabled = not M.is_enabled
        if M.is_enabled then
            print("Syntax Gaslighting enabled! Prepare to question everything...")
            M.schedule_update()
        else
            print("Syntax Gaslighting disabled. You can code in peace now.")
            local bufnr = api.nvim_get_current_buf()
            api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
        end
    end, {})

    -- Change the gaslighting chance percentage.
    api.nvim_create_user_command("SyntaxGaslightingEditChance", function()
        local input = vim.fn.input("Enter the percentage chance of gaslighting (1-100): ", config.gaslighting_chance)
        local num = tonumber(input)
        if num and num >= 1 and num <= 100 then
            config.gaslighting_chance = num
            print("Gaslighting chance set to " .. config.gaslighting_chance .. "%")
            M.schedule_update()
        else
            print("Invalid input. Please enter a number between 1 and 100.")
        end
    end, {})

    api.nvim_create_user_command("SyntaxGaslightingMessages", function()
        print("Current gaslighting messages:")
        for _, msg in ipairs(config.messages) do
            print("- " .. msg)
        end
    end, {})
end

-- A simple, deterministic hash function using sha256
---@param str string
---@return string
local function createHash(str)
    return vim.fn.sha256(str)
end

--- Check if the current filetype should be ignored
---@return boolean
local function shouldIgnoreFileType()
    return ignored_filetypes_set[vim.bo.filetype] or false
end

--- Determine if a gaslighting message should be applied to a line
---@param line string
---@return string|nil
local function getGaslightingMessageForLineContent(line)
    local hash = createHash(line)
    local selectionNum = tonumber(hash:sub(1, 8), 16)
    local messageNum = tonumber(hash:sub(-8), 16)
    if (selectionNum % 100) < config.gaslighting_chance then
        local messageIndex = (messageNum % #config.messages) + 1
        return config.messages[messageIndex]
    end
    return nil
end

-- Check if the line is a comment based on the filetype
-- TODO: this should be replaced with Treesitter native method of checking for comments
-- in the future. I don't care to set up Treesitter for testing, so this is what we have.
local function isComment(line)
    local filetype = vim.bo.filetype
    local trimmed_line = vim.trim(line)

    -- Lua: '--' for comments
    if filetype == "lua" then
        return vim.fn.match(trimmed_line, "^--") ~= -1
    end

    -- Python: '#' for comments
    if filetype == "python" then
        return vim.fn.match(trimmed_line, "^#") ~= -1
    end

    -- C/C++/JavaScript: '//' for comments
    if filetype == "c" or filetype == "cpp" or filetype == "javascript" or filetype == "java" then
        return vim.fn.match(trimmed_line, "^//") ~= -1
    end

    -- If no specific filetype matches, return false (i.e., not a comment)
    return false
end

--- Update the gaslighting decorations in the current buffer
function M.update_decorations()
    if not M.is_enabled or shouldIgnoreFileType() then return end

    local bufnr = api.nvim_get_current_buf()
    api.nvim_buf_clear_namespace(bufnr, ns, 0, -1) -- Clear previous decorations
    local lines = api.nvim_buf_get_lines(bufnr, 0, -1, false)

    -- Track processed lines to avoid duplicates
    local processed_hashes = {}

    for i, line in ipairs(lines) do
        local trimmed = vim.trim(line)

        -- Skip comment lines entirely
        if #trimmed >= config.min_line_length and not isComment(trimmed) then
            local hash = createHash(trimmed)

            if not processed_hashes[hash] then
                processed_hashes[hash] = true
                local message = getGaslightingMessageForLineContent(trimmed)
                if message then
                    local first_non_whitespace = line:find("%S")
                    if first_non_whitespace then
                        api.nvim_buf_set_extmark(bufnr, ns, i - 1, first_non_whitespace - 1, {
                            virt_text = { { message, config.highlight } },
                            virt_text_pos = "eol",
                            hl_mode = "combine",
                        })
                    end
                end
            end
        end
    end
end

--- Debounced update function
function M.schedule_update()
    local uv = vim.uv or vim.loop

    -- Properly clean up the previous timer before creating a new one.
    -- Do NOT move this block below `uv.new_timer()`, or the new timer
    -- will be stopped and closed immediately after being created.
    if timer then
        if timer.stop then timer:stop() end
        if timer.close then timer:close() end
    end

    timer = uv.new_timer()

    -- Ensure the new timer is valid before starting it.
    if timer then
        timer:start(config.debounce_delay, 0, vim.schedule_wrap(M.update_decorations))
    end
end

return M
