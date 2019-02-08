-- This file is part of davt.
--
-- Developed for the LSST Data Management System.
-- This product includes software developed by the LSST Project
-- (https://www.lsst.org).
-- See the COPYRIGHT file at the top-level directory of this distribution
-- for details of code ownership.
--
-- This program is free software: you can redistribute it and/or modify
-- it under the terms of the GNU General Public License as published by
-- the Free Software Foundation, either version 3 of the License, or
-- (at your option) any later version.
--
-- This program is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU General Public License for more details.
--
-- You should have received a copy of the GNU General Public License
-- along with this program.  If not, see <https://www.gnu.org/licenses/>.


local ffi = require("ffi")
local syscall_api = require("syscall") -- loads ffi.C for us

-- What's missing in ljsyscall
ffi.cdef [[
    int initgroups(const char *user, gid_t group);
    struct passwd {
        char   *pw_name;
        char   *pw_passwd;
        uid_t   pw_uid;
        gid_t   pw_gid;
        char   *pw_gecos;
        char   *pw_dir;
        char   *pw_shell;
    };
    struct passwd *getpwnam(const char *name);
    struct passwd *getpwuid(uid_t uid);
    int setfsuid(uid_t fsuid);
    int setfsgid(uid_t fsgid);
]]

local davt = {}
local NOBODY = 65534
local MAX_RESERVED_ID = 499

local function _initgroups(user, gid)
    return ffi.C.initgroups(user, gid) == 0
end

local function _setfsuid(id)
    return ffi.C.setfsuid(ffi.typeof("unsigned int")(id))
end

local function _setfsgid(id)
    return ffi.C.setfsgid(ffi.typeof("unsigned int")(id))
end

--- Sanitize a uid or gid.
-- We do not allow impersonation of reserved id numbers (< 500)
local function _assert_valid_id(id)
    id = tonumber(id)
    if id == nil or id <= MAX_RESERVED_ID then
        ngx.log(ngx.CRIT, "davt: invalid id or no id specified")
        ngx.exit(ngx.HTTP_INTERNAL_SERVER_ERROR)
    end
end

--- Create a new davt object
-- @param opts The options, only `secret` is used. If opts.secret is nil,
-- then we ALWAYS create a random secret so we are secure by default. If
-- it's desired to disable secret checking, than opt.secret should be set
-- to the empty string.
function davt:new(opts)
    new_davt = opts or {}   -- create object if user does not provide one
    setmetatable(new_davt, self)
    self.__index = self

    if new_davt.secret == nil then
        ngx.log(ngx.WARN, "davt: secret isn't set. Setting a new secret")
        local buf = ffi.typeof("char[?]")(32)
        local _, err = syscall_api.getrandom(buf, 32)
        if err ~= nil then
            ngx.log(ngx.CRIT, "davt: error initializing secret")
            ngx.exit(ngx.HTTP_INTERNAL_SERVER_ERROR)
        end
        local buf64 = ngx.encode_base64(ffi.string(buf))
        new_davt.secret = string.gsub(buf64, "=", "")
        ngx.log(ngx.NOTICE, "davt: expecting secret in x-davt-secret header: "
                .. new_davt.secret)
    end
    return new_davt
end

--- Check access
-- This function checks access for every request. Either the "x-davt-secret"
-- header MUST be set to the secret configured in `lua_davt:new` OR,
-- if the empty string is configured for the secret, than x-davt-secret must
-- either be omitted or also an empty string.
function davt:check_access()
    -- The secret can never be nil, but it can be an empty string
    if self.secret == nil then
        ngx.log(ngx.CRIT, "davt: secret isn't set. See `davt:new`.")
        ngx.exit(ngx.HTTP_INTERNAL_SERVER_ERROR)
    end

    -- We want to always check against a string _in case_ the user EXPLICITLY
    -- set the secret to an empty string
    local davt_secret_header = ngx.req.get_headers()['x-davt-secret'] or ""
    if self.secret ~= davt_secret_header then
        ngx.log(ngx.CRIT, "davt: unable to validate secret header")
        ngx.exit(ngx.HTTP_INTERNAL_SERVER_ERROR)
    end
end

--- Clear the uid, gid, and supplementary groups for the process.
function davt:nobody()
    new_davt:setfsuid(NOBODY)
    new_davt:setfsgid(NOBODY)
    new_davt:setgroups({})
end

--- Set the File System UID for the process.
-- This is the nginx-friendly function.
-- @param uid The UID of the user for filesystem operations.
function davt:setfsuid(uid)
    self:check_access()

    uid = _assert_valid_id(uid)

    -- Two calls are always needed for setfsuid
    _setfsuid(uid)
    local actual = _setfsuid(uid)

    if actual ~= uid then
        ngx.log(ngx.CRIT, "davt: setfsuid failed")
        ngx.exit(ngx.HTTP_INTERNAL_SERVER_ERROR)
    end
end

--- Set the File System GID for the process.
-- This is the nginx-friendly function.
-- @param gid The GID of the user for filesystem operations.
function davt:setfsgid(gid)
    self:check_access()

    gid = _assert_valid_id(gid)

    -- Two calls are always needed for setfsgid
    _setfsgid(gid)
    local actual = _setfsgid(gid)

    if actual ~= gid then
        ngx.log(ngx.CRIT, "davt: setfsgid failed")
        ngx.exit(ngx.HTTP_INTERNAL_SERVER_ERROR)
    end
end

--- Init groups for a user with a given GID
-- This is the nginx-friendly function.
-- **This function requires passwd/group information
-- to be available to the host.**
--
-- @param username
-- @param gid The GID for filesystem operations.
function davt:initgroups(username, gid)
    self:check_access()

    gid = _assert_valid_id(gid)
    if not _initgroups(username, gid) then
        ngx.log(ngx.CRIT, "davt: initgroups failed")
        ngx.exit(ngx.HTTP_INTERNAL_SERVER_ERROR)
    end
end

--- Set supplementary groups for a user.
-- This is the nginx-friendly function.
--
-- @param groups list of the supplementary groups for the user
function davt:setgroups(groups)
    self:check_access()

    _groups = {}
    for i, group in ipairs(groups) do
        group = _assert_valid_id(group)
        _groups[i] = group
    end
    if not syscall_api.setgroups(_groups) then
        ngx.log(ngx.CRIT, "davt: setgroups failed")
        ngx.exit(ngx.HTTP_INTERNAL_SERVER_ERROR)
    end
end

--- Initialize a user for the process.
-- This is the nginx-friendly function.
-- Provide either the username or the UID and
-- impersonate a user through intialization.
-- **This function requires passwd/group information
-- to be available to the host.**
--
-- @param username the username of the user; or
-- @param uid the uid of the user
function davt:init_user(username, uid)
    self:check_access()

    local passwd
    if username then
        passwd = ffi.C.getpwnam(username)
    elseif uid then
        uid = _assert_valid_id(uid)
        passwd = ffi.C.getpwuid(uid)
    end

    if passwd == nil then
        ngx.log(ngx.CRIT, "davt: no valid username or id specified")
        ngx.exit(ngx.HTTP_INTERNAL_SERVER_ERROR)
    end

    -- Could get UID and groups here from REMOTE_USER via /etc/passwd
    -- Set FSUID
    ngx.log(ngx.NOTICE, "davt: [Impersonating UID #" .. passwd.pw_uid ..
            ", GID #" .. passwd.pw_gid .. "]")
    self:setfsuid(passwd.pw_uid)
    self:setfsgid(passwd.pw_gid)
    self:initgroups(passwd.pw_name, passwd.pw_gid)
end

--- Set a user for the process.
-- This is the nginx-friendly function.
-- Provide either the uid, primary gid, and collection
-- of supplementary gids and impersonate a user.
--
-- Use this function if you do not have passwd/group
-- information available on the host.
--
-- @param uid the UID of the user
-- @param gid the GID of the user
-- @param groups the collection of supplementary GIDs for the user
function davt:set_user(uid, gid, groups)
    self:check_access()

    ngx.log(ngx.NOTICE, "davt: [Impersonating UID #" .. uid ..
            ", GID #" .. gid .. "]")
    self:setfsuid(uid)
    self:setfsgid(gid)
    self:setgroups(groups)
end

function davt:init_user_from_uid(uid)
    return self:init_user(nil, uid)
end

function davt:init_user_from_username(username)
    return self:init_user(username, nil)
end

return davt
