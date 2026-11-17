-- Neovim as kitty's scrollback pager: a vim "copy mode" for the terminal.
-- Opened with Alt+Esc (alt+escape in kitty.conf). Used only for the
-- pager (nvim -u this file), so a normal nvim never reads it.
--
--   hjkl, w/b, /search, gg/G ...   move as usual
--   v  V  Ctrl+v                   visual, visual line, visual block
--   y                              copy to the system clipboard (xclip)
--   q                              close and go back to the terminal
--
-- kitty pipes the scrollback in with its colors (ANSI codes) on stdin; it is
-- drawn in a terminal buffer so it looks the way it did on screen.

vim.o.clipboard = "unnamedplus"   -- y copies to the system clipboard
vim.o.shada = ""                  -- no history/marks file
vim.o.swapfile = false
vim.o.number = false
vim.o.relativenumber = false
vim.o.signcolumn = "no"
vim.o.laststatus = 0
vim.o.showtabline = 0
vim.o.showmode = true             -- shows -- VISUAL -- / -- VISUAL LINE --
vim.o.ruler = false
vim.o.cmdheight = 1
vim.o.scrolloff = 4
vim.o.ignorecase = true
vim.o.smartcase = true
vim.o.termguicolors = true

local function quit() vim.cmd("qa!") end

vim.api.nvim_create_autocmd("VimEnter", {
  once = true,
  callback = function()
    local text_buf = vim.api.nvim_get_current_buf()
    local lines = vim.api.nvim_buf_get_lines(text_buf, 0, -1, false)
    -- drop trailing empty lines, so the view ends at the last output
    while #lines > 0 and lines[#lines]:gsub("\27%[[%d;]*m", "") == "" do
      table.remove(lines)
    end

    local term_buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_win_set_buf(0, term_buf)
    local chan = vim.api.nvim_open_term(term_buf, {})
    vim.api.nvim_chan_send(chan, table.concat(lines, "\r\n"))
    vim.api.nvim_buf_delete(text_buf, { force = true })

    -- q closes; keys that would type into the (dead) terminal do nothing
    for _, key in ipairs({ "q", "Q" }) do
      vim.keymap.set("n", key, quit, { buffer = term_buf, nowait = true })
    end
    for _, key in ipairs({ "i", "I", "a", "A", "o", "O" }) do
      vim.keymap.set("n", key, "<Nop>", { buffer = term_buf })
    end
    vim.keymap.set("n", "<Esc>", "<Cmd>nohlsearch<CR>", { buffer = term_buf })

    -- start at the bottom, where the screen was, once the text is drawn
    vim.defer_fn(function()
      vim.cmd("normal! G")
      vim.cmd("normal! 0")
    end, 30)
  end,
})
