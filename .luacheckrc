-- Don't report unused self arguments of methods.
self = false

-- Rerun tests only if their modification time changed.
cache = true

ignore = {
    "631", -- max_line_length
}

-- Global objects defined by the C code
globals = { "vim" }

-- vim: ft=lua tw=80
