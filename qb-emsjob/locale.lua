-- Minimal locale layer shared by client & server (no external dependency).
-- Set the language with `set qb_locale en` in your server.cfg.

Lang = Lang or {}

local function currentLocale()
    local l = GetConvar('qb_locale', 'en')
    if not l or l == '' then l = 'en' end
    return l
end

--- Translate a key, substituting {placeholder} values from the vars table.
--- @param key string
--- @param vars table|nil
function Lang:t(key, vars)
    local locale = currentLocale()
    local dict = Locales and (Locales[locale] or Locales['en']) or nil
    local str = dict and dict[key] or nil
    if type(str) ~= 'string' then
        str = Locales and Locales['en'] and Locales['en'][key] or nil
    end
    if type(str) ~= 'string' then return key end
    if vars then
        for k, v in pairs(vars) do
            str = str:gsub('{' .. tostring(k) .. '}', tostring(v))
        end
    end
    return str
end

--- Shorthand: _L('key', { ... })
function _L(key, vars)
    return Lang:t(key, vars)
end
