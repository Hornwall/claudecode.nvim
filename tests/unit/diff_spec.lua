-- luacheck: globals expect
require("tests.busted_setup")

describe("Diff Module", function()
  local diff

  local original_vim_functions = {}

  local function setup()
    package.loaded["claudecode.diff"] = nil
    package.loaded["claudecode.config"] = nil

    assert(_G.vim, "Global vim mock not initialized by busted_setup.lua")
    assert(_G.vim.fn, "Global vim.fn mock not initialized")

    -- For this spec, the global mock (which now includes stdpath) should be largely sufficient.
    -- The local mock_vim that was missing stdpath is removed.

    diff = require("claudecode.diff")
  end

  local function teardown()
    for path, func in pairs(original_vim_functions) do
      local parts = {}
      for part in string.gmatch(path, "[^%.]+") do
        table.insert(parts, part)
      end
      local obj = _G.vim
      for i = 1, #parts - 1 do
        obj = obj[parts[i]]
      end
      obj[parts[#parts]] = func
    end
    original_vim_functions = {}

    if original_vim_functions["cmd"] then
      _G.vim.cmd = original_vim_functions["cmd"]
      original_vim_functions["cmd"] = nil
    end

    -- _G.vim itself is managed by busted_setup.lua
  end

  before_each(function()
    setup()
  end)

  after_each(function()
    teardown()
  end)

  describe("Provider Detection", function()
    it("should detect when diffview.nvim is not available", function()
      local old_require = require
      _G.require = function(name)
        if name == "diffview" then
          error("module 'diffview' not found")
        end
        return old_require(name)
      end

      local available = diff.is_diffview_available()
      expect(available).to_be_false()

      _G.require = old_require
    end)

    it("should detect when diffview.nvim is available", function()
      local old_require = require
      _G.require = function(name)
        if name == "diffview" then
          return {}
        end
        return old_require(name)
      end

      local available = diff.is_diffview_available()
      expect(available).to_be_true()

      _G.require = old_require
    end)
  end)

  describe("Provider Selection", function()
    it("should return native when diffview is not available and provider is auto", function()
      diff.setup({ diff_provider = "auto" })

      local old_require = require
      _G.require = function(name)
        if name == "diffview" then
          error("module 'diffview' not found")
        end
        return old_require(name)
      end

      local provider = diff.get_current_provider()
      expect(provider).to_be("native")

      _G.require = old_require
    end)

    it("should return diffview when available and provider is auto", function()
      diff.setup({ diff_provider = "auto" })

      local old_require = require
      _G.require = function(name)
        if name == "diffview" then
          return {}
        end
        return old_require(name)
      end

      local provider = diff.get_current_provider()
      expect(provider).to_be("diffview")

      _G.require = old_require
    end)

    it("should return native when provider is explicitly set to native", function()
      diff.setup({ diff_provider = "native" })

      local provider = diff.get_current_provider()
      expect(provider).to_be("native")
    end)

    it("should fallback to native when diffview provider is set but not available", function()
      diff.setup({ diff_provider = "diffview" })

      local old_require = require
      _G.require = function(name)
        if name == "diffview" then
          error("module 'diffview' not found")
        end
        return old_require(name)
      end

      local provider = diff.get_current_provider()
      expect(provider).to_be("native")

      _G.require = old_require
    end)
  end)

  describe("Temporary File Management", function()
    it("should create temporary files with correct content", function()
      local test_content = "This is test content\nLine 2\nLine 3"
      local test_filename = "test.lua"

      local mock_file = {
        write = function() end,
        close = function() end,
      }
      local old_io_open = io.open
      rawset(io, "open", function()
        return mock_file
      end)

      local tmp_file, err = diff._create_temp_file(test_content, test_filename)

      expect(tmp_file).to_be_string()
      expect(err).to_be_nil()

      local tmp_file_str = tostring(tmp_file)
      expect(tmp_file_str:find("claudecode_diff", 1, true)).not_to_be_nil()
      expect(tmp_file_str:find(test_filename, 1, true)).not_to_be_nil()

      rawset(io, "open", old_io_open)
    end)

    it("should handle file creation errors", function()
      local test_content = "test"
      local test_filename = "test.lua"

      local old_io_open = io.open
      rawset(io, "open", function()
        return nil
      end)

      local tmp_file, err = diff._create_temp_file(test_content, test_filename)

      expect(tmp_file).to_be_nil()
      expect(err).to_be_string()
      expect(err:find("Failed to create temporary file", 1, true)).not_to_be_nil()

      rawset(io, "open", old_io_open)
    end)
  end)

  describe("Native Diff Implementation", function()
    it("should create diff with correct parameters", function()
      diff.setup({
        diff_provider = "native",
        diff_opts = {
          vertical_split = true,
          show_diff_stats = false,
          auto_close_on_accept = true,
        },
      })

      local commands = {}
      if _G.vim and rawget(original_vim_functions, "cmd") == nil then
        original_vim_functions["cmd"] = _G.vim.cmd
      end
      _G.vim.cmd = function(cmd)
        table.insert(commands, cmd)
      end

      local mock_file = {
        write = function() end,
        close = function() end,
      }
      local old_io_open = io.open
      rawset(io, "open", function()
        return mock_file
      end)

      local result = diff._open_native_diff("/path/to/old.lua", "/path/to/new.lua", "new content here", "Test Diff")

      expect(result.success).to_be_true()
      expect(result.provider).to_be("native")
      expect(result.tab_name).to_be("Test Diff")

      local found_tabnew = false
      local found_diffthis = false
      local found_vertical_split = false

      for _, cmd in ipairs(commands) do
        if cmd:find("tabnew", 1, true) then
          found_tabnew = true
        end
        if cmd:find("diffthis", 1, true) then
          found_diffthis = true
        end
        if cmd:find("vertical split", 1, true) then
          found_vertical_split = true
        end
      end

      expect(found_tabnew).to_be_true()
      expect(found_diffthis).to_be_true()
      expect(found_vertical_split).to_be_true()

      rawset(io, "open", old_io_open)
    end)

    it("should use horizontal split when configured", function()
      diff.setup({
        diff_provider = "native",
        diff_opts = {
          vertical_split = false,
          show_diff_stats = false,
          auto_close_on_accept = true,
        },
      })

      local commands = {}
      if _G.vim and rawget(original_vim_functions, "cmd") == nil then
        original_vim_functions["cmd"] = _G.vim.cmd
      end
      _G.vim.cmd = function(cmd)
        table.insert(commands, cmd)
      end

      local mock_file = {
        write = function() end,
        close = function() end,
      }
      local old_io_open = io.open
      rawset(io, "open", function()
        return mock_file
      end)

      local result = diff._open_native_diff("/path/to/old.lua", "/path/to/new.lua", "new content here", "Test Diff")

      expect(result.success).to_be_true()
      local found_split = false
      local found_vertical_split = false

      for _, cmd in ipairs(commands) do
        if cmd:find("split", 1, true) and not cmd:find("vertical split", 1, true) then
          found_split = true
        end
        if cmd:find("vertical split", 1, true) then
          found_vertical_split = true
        end
      end

      expect(found_split).to_be_true()
      expect(found_vertical_split).to_be_false()

      rawset(io, "open", old_io_open)
    end)

    it("should handle temporary file creation errors", function()
      diff.setup({ diff_provider = "native" })

      local old_io_open = io.open
      rawset(io, "open", function()
        return nil
      end)

      local result = diff._open_native_diff("/path/to/old.lua", "/path/to/new.lua", "new content here", "Test Diff")

      expect(result.success).to_be_false()
      expect(result.error).to_be_string()
      expect(result.error:find("Failed to create temporary file", 1, true)).not_to_be_nil()

      rawset(io, "open", old_io_open)
    end)
  end)

  describe("Open Diff Function", function()
    it("should use native provider when configured", function()
      diff.setup({ diff_provider = "native" })

      local native_called = false
      diff._open_native_diff = function(old_path, new_path, content, tab_name)
        native_called = true
        return {
          success = true,
          provider = "native",
          tab_name = tab_name,
        }
      end

      local result = diff.open_diff("/path/to/old.lua", "/path/to/new.lua", "new content", "Test Diff")

      expect(native_called).to_be_true()
      expect(result.provider).to_be("native")
      expect(result.success).to_be_true()
    end)

    it("should use diffview provider when available and configured", function()
      diff.setup({ diff_provider = "diffview" })

      local old_require = require
      _G.require = function(name)
        if name == "diffview" then
          return {}
        end
        return old_require(name)
      end

      local diffview_called = false
      diff._open_diffview_diff = function(old_path, new_path, content, tab_name)
        diffview_called = true
        return {
          success = true,
          provider = "diffview",
          tab_name = tab_name,
        }
      end

      local result = diff.open_diff("/path/to/old.lua", "/path/to/new.lua", "new content", "Test Diff")

      expect(diffview_called).to_be_true()
      expect(result.provider).to_be("diffview")

      _G.require = old_require
    end)
  end)

  teardown()
end)
