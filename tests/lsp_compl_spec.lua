local api = vim.api
local compl = require('lsp_compl')

local messages = {}

local function new_server(completion_result)
  local function server(dispatchers)
    local closing = false
    local srv = {}

    function srv.request(method, params, callback)
      table.insert(messages, {
        method = method,
        params = params,
      })
      if method == 'initialize' then
        callback(nil, {
          capabilities = {
            completionProvider = {
              triggerCharacters = {'.'}
            }
          }
        })
      elseif method == 'textDocument/completion' then
        callback(nil, completion_result)
      elseif method == 'shutdown' then
        callback(nil, nil)
      end
    end

    function srv.notify(method, _)
      if method == 'exit' then
        dispatchers.on_exit(0, 15)
      end
    end

    function srv.is_closing()
      return closing
    end

    function srv.terminate()
      closing = true
    end

    return srv
  end
  return server
end


local function wait(condition, msg)
  vim.wait(100, condition)
  local result = condition()
  assert.are_not.same(false, result, msg)
  assert.are_not.same(nil, result, msg)
end


describe('lsp_compl', function()
  local buf = api.nvim_create_buf(false, true)
  local win = api.nvim_get_current_win()
  local capture = {}
  vim.fn.complete = function(col, matches)
    capture.col = col
    capture.matches = matches
  end
  api.nvim_get_mode = function()
    return {
      mode = 'i'
    }
  end
  api.nvim_win_set_buf(win, buf)

  before_each(function()
    capture = {}
    messages = {}
  end)

  after_each(function()
    vim.lsp.stop_client(vim.lsp.get_active_clients())
    wait(function() return vim.tbl_count(vim.lsp.get_active_clients()) == 0 end, 'clients must stop')
  end)

  it('fetches completions and shows them using complete on trigger_completion', function()
    local completion_result = {
      isIncomplete = false,
      items = {
        {
          label = 'hello',
        }
      }
    }
    local server = new_server(completion_result)
    vim.lsp.start({ name = 'fake-server', cmd = server, on_attach = compl.attach })
    api.nvim_buf_set_lines(buf, 0, -1, true, {'a'})
    api.nvim_win_set_cursor(win, { 1, 1 })
    compl.trigger_completion()
    wait(function() return capture.col ~= nil end)
    assert.are.same(2, #messages)
    local expected_matches = {
      {
        abbr = 'hello',
        dup = 1,
        empty = 1,
        equal = 0,
        icase = 1,
        info = '',
        kind = '',
        menu = '',
        user_data = {
          label = 'hello',
        },
        word = 'hello'
      }
    }
    assert.are.same(expected_matches, capture.matches)
  end)

  it('merges results from multiple clients', function()
    local server1 = new_server({
      isIncomplete = false,
      items = {
        {
          label = 'hello',
        }
      }
    })
    vim.lsp.start({ name = 'server1', cmd = server1, on_attach = compl.attach })
    local server2 = new_server({
      isIncomplete = false,
      items = {
        {
          label = 'hallo',
        }
      }
    })
    vim.lsp.start({ name = 'server2', cmd = server2, on_attach = compl.attach })
    api.nvim_buf_set_lines(buf, 0, -1, true, {'a'})
    api.nvim_win_set_cursor(win, { 1, 1 })
    compl.trigger_completion()
    wait(function() return capture.col ~= nil end)
    assert.are.same(2, #capture.matches)
    assert.are.same('hello', capture.matches[1].word)
    assert.are.same('hallo', capture.matches[2].word)
  end)

  it('uses defaults from itemDefaults', function()
    local server = new_server({
      isIncomplete = false,
      itemDefaults = {
        editRange = {
          start = { line = 1, character = 1 },
          ['end'] = { line = 1, character = 4 },
        },
        insertTextFormat = 2,
        data = 'foobar',
      },
      items = {
        {
          label = 'hello',
          data = 'item-property-has-priority',
          textEditText ='hello',
        }
      }
    })
    vim.lsp.start({ name = 'server', cmd = server, on_attach = compl.attach })
    api.nvim_buf_set_lines(buf, 0, -1, true, {'a'})
    api.nvim_win_set_cursor(win, { 1, 1 })
    compl.trigger_completion()
    local candidate = capture.matches[1]
    assert.are.same('hello', candidate.word)
    assert.are.same(2, candidate.user_data.insertTextFormat)
    assert.are.same('item-property-has-priority', candidate.user_data.data)
    assert.are.same({ line = 1, character = 1}, candidate.user_data.textEdit.range.start)
  end)
end)