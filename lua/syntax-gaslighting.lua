local M = {}

-- Default configuration options
local default_config = {
    gaslighting_chance = 5,             -- 5% chance per line
    min_line_length = 10,               -- Minimum trimmed line length to apply gaslighting
    highlight = "GaslightingUnderline", -- Highlight group name (linked to Comment by default)
    debounce_delay = 500,               -- Debounce delay in ms
    auto_update = true,                 -- Whether to auto-update on buffer events
    merge_messages = false,             -- If true, merge user messages with default ones
    filetypes_to_ignore = {             -- List of filetypes to ignore (default: "netrw")
        "netrw",
        "NvimTree",
        "neo-tree",
        "Telescope",
        "qf"
    },
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

local config = {}
local api = vim.api
local timer = nil
local ns = api.nvim_create_namespace("syntax_gaslighting")
M.is_enabled = true

-- If user_config.merge_messages is true and user_config.messages is provided,
-- the plugin will merge default messages with user messages.
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

    -- Command to toggle the gaslighting functionality.
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

    -- Command to change the gaslighting chance percentage.
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
end

-- A simple deterministic hash function (not cryptographically secure)
local function createHash(str)
    local hash1, hash2 = 0, 0
    for i = 1, #str do
        local byte = str:byte(i)
        hash1 = (hash1 * 31 + byte) % 0xFFFFFFFF
        hash2 = (hash2 * 37 + byte) % 0xFFFFFFFF
    end
    return string.format("%08x%08x", hash1, hash2)
end

-- Check if the current buffer's filetype is in the ignore list
local function shouldIgnoreFileType()
    local filetype = vim.bo.filetype
    for _, ft in ipairs(config.filetypes_to_ignore) do
        if filetype == ft then
            return true
        end
    end
    return false
end

-- Determine if a gaslighting message should be applied to a line and return it if so.
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

-- Update the gaslighting decorations in the current buffer.
function M.update_decorations()
    if not M.is_enabled or shouldIgnoreFileType() then
        return
    end

    local bufnr = api.nvim_get_current_buf()
    -- Clear previous extmarks in our namespace.
    api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
    local lines = api.nvim_buf_get_lines(bufnr, 0, -1, false)
    for i, line in ipairs(lines) do
        local trimmed = vim.trim(line)
        if #trimmed >= config.min_line_length then
            -- Skip dummy comment lines (detection based on starting patterns)
            -- TODO: use Treesitter for this
            if not (trimmed:find("^//") or trimmed:find("^#") or trimmed:find("^/%*") or trimmed:find("^%*") or trimmed:find("^<!--")) then
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

-- Debounce update: schedules an update after a delay.
function M.schedule_update()
    if timer then
        timer:stop()
        timer:close()
    end
    timer = vim.loop.new_timer()
    timer:start(config.debounce_delay, 0, vim.schedule_wrap(function()
        M.update_decorations()
    end))
end

return M
