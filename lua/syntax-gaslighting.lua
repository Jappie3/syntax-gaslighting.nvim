local api = vim.api

local DEFAULT_GASLIGHTING_CHANCE = 5 -- 5% chance per line
local MIN_LINE_LENGTH = 10           -- minimum trimmed line length to apply gaslighting
local GASLIGHTING_MESSAGES = {
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
}

-- Plugin state
local is_enabled = true
local gaslighting_chance_percentage = DEFAULT_GASLIGHTING_CHANCE
local ns = api.nvim_create_namespace("syntax_gaslighting")

vim.cmd("highlight default link GaslightingUnderline Comment")

local function createHash(str)
    local hash1, hash2 = 0, 0
    for i = 1, #str do
        local byte = str:byte(i)
        hash1 = (hash1 * 31 + byte) % 0xFFFFFFFF
        hash2 = (hash2 * 37 + byte) % 0xFFFFFFFF
    end
    return string.format("%08x%08x", hash1, hash2)
end

-- Given a line of code, decide if a gaslighting message should be applied
-- and return the selected message if so.
local function getGaslightingMessageForLineContent(line)
    local hash = createHash(line)
    local selectionNum = tonumber(hash:sub(1, 8), 16)
    local messageNum = tonumber(hash:sub(-8), 16)
    if (selectionNum % 100) < gaslighting_chance_percentage then
        local messageIndex = (messageNum % #GASLIGHTING_MESSAGES) + 1
        return GASLIGHTING_MESSAGES[messageIndex]
    end
    return nil
end

-- Update the gaslighting decorations in the current buffer.
local function update_gaslighting_decorations()
    if not is_enabled then
        return
    end

    local bufnr = api.nvim_get_current_buf()
    -- Clear previous extmarks in our namespace
    api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
    local lines = api.nvim_buf_get_lines(bufnr, 0, -1, false)
    for i, line in ipairs(lines) do
        local trimmed = vim.trim(line)
        if #trimmed >= MIN_LINE_LENGTH then
            -- Skip dummy comment lines (detection based on starting patterns)
            -- There can be some native API for integration, but I'm not sure.
            if not (trimmed:find("^//") or trimmed:find("^#") or trimmed:find("^/%*") or trimmed:find("^%*") or trimmed:find("^<!--")) then
                local message = getGaslightingMessageForLineContent(trimmed)
                if message then
                    local first_non_whitespace = line:find("%S")
                    if first_non_whitespace then
                        api.nvim_buf_set_extmark(bufnr, ns, i - 1, first_non_whitespace - 1, {
                            virt_text = { { message, "GaslightingUnderline" } },
                            virt_text_pos = "eol",
                            hl_mode = "combine",
                        })
                    end
                end
            end
        end
    end
end

-- Debounce update (updates after 500ms of inactivity)
local timer = nil
local function schedule_update()
    if timer then
        timer:stop()
        timer:close()
    end
    timer = vim.loop.new_timer()
    timer:start(500, 0, vim.schedule_wrap(function()
        update_gaslighting_decorations()
    end))
end

-- Setup autocommands to update decorations on buffer enter and changes.
api.nvim_create_autocmd({ "BufEnter", "TextChanged", "TextChangedI" }, {
    callback = function()
        schedule_update()
    end,
})

-- Command to toggle the gaslighting functionality.
vim.api.nvim_create_user_command("SyntaxGaslightingToggle", function()
    is_enabled = not is_enabled
    if is_enabled then
        print("Syntax Gaslighting enabled! Prepare to question everything...")
        schedule_update()
    else
        print("Syntax Gaslighting disabled. You can code in peace now.")
        local bufnr = api.nvim_get_current_buf()
        api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
    end
end, {})

-- Command to change the gaslighting chance percentage.
vim.api.nvim_create_user_command("SyntaxGaslightingEditChance", function()
    local input = vim.fn.input("Enter the percentage chance of gaslighting (1-100): ", gaslighting_chance_percentage)
    local num = tonumber(input)
    if num and num >= 1 and num <= 100 then
        gaslighting_chance_percentage = num
        print("Gaslighting chance set to " .. gaslighting_chance_percentage .. "%")
        schedule_update()
    else
        print("Invalid input. Please enter a number between 1 and 100.")
    end
end, {})

return {
    update = update_gaslighting_decorations,
}
