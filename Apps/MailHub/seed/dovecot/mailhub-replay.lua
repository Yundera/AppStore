-- MailHub: record each IMAP action on the local mailbox as one JSON line.
-- Only records; mailhub-mirror replays Live/ actions at the provider. Changes the
-- mirror writes straight into Maildir go through no IMAP command, so never show here.
local QUEUE = "/srv/vmail/%s/live-queue/events.jsonl"

local function esc(s)
  return (tostring(s):gsub("[%c\"\\]", function(c) return string.format("\\u%04x", c:byte()) end))
end
local function encode(v)
  local t = type(v)
  if t == "table" then
    local parts, is_list = {}, (#v > 0)
    for k, x in pairs(v) do
      if is_list then table.insert(parts, encode(x))
      else table.insert(parts, "\"" .. esc(k) .. "\":" .. encode(x)) end
    end
    return is_list and ("[" .. table.concat(parts, ",") .. "]") or ("{" .. table.concat(parts, ",") .. "}")
  elseif t == "number" or t == "boolean" then return tostring(v)
  else return "\"" .. esc(v) .. "\"" end
end

function dovecot_lua_notify_begin_txn(user)
  return { user = user.username, events = {} }
end
local function add(name)
  return function(ctx, event) event.event = name; table.insert(ctx.events, event) end
end
dovecot_lua_notify_event_message_new = add("MessageNew")
dovecot_lua_notify_event_message_append = add("MessageAppend")
dovecot_lua_notify_event_message_expunge = add("MessageExpunge")
dovecot_lua_notify_event_flags_set = add("FlagsSet")
dovecot_lua_notify_event_flags_clear = add("FlagsClear")
dovecot_lua_notify_event_message_read = add("MessageRead")
dovecot_lua_notify_event_message_trash = add("MessageTrash")
dovecot_lua_notify_event_mailbox_create = add("MailboxCreate")
dovecot_lua_notify_event_mailbox_delete = add("MailboxDelete")
dovecot_lua_notify_event_mailbox_rename = add("MailboxRename")

function dovecot_lua_notify_end_txn(ctx, success)
  if not success or #ctx.events == 0 then return end
  local f = io.open(string.format(QUEUE, ctx.user), "a")
  if not f then return end
  for _, e in ipairs(ctx.events) do
    e.at = os.time()
    f:write(encode(e), "\n")
  end
  f:close()
end
