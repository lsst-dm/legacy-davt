local ffi = require("ffi")
local syscall_api = require("syscall") -- loads ffi.C for us
local nr = require("syscall.linux.nr")

-- What's missing in ljsyscall
ffi.cdef[[
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
]]

local M = {}

local function _initgroups(user, gid)
    return ffi.C.initgroups(user, gid) == 0
end


local function _setfsuid(id)
    return tonumber(ffi.C.syscall(nr.SYS.setfsuid, ffi.typeof("unsigned int")(id)))
end

--- Set the File System UID for the process.
-- This is the nginx-friendly function.
-- @param uid The UID of the user for filesytem operations.
local function setfsuid(uid)
    -- Note: This is possibly unecessary, as it appears to be the case that
    -- files are always opened in the worker process and _often_
    -- processed in a thread, and that once you have the handle it's
    -- the file system wiill always honor it. So, it may be the case that
    -- setuid would work just fine, but setfsuid is still nice because you
    -- don't need to worry about saved UIDs

    -- Two calls are always needed for setfsuid
    if uid == nil or uid == 0 then
        ngx.log(ngx.CRIT, "Unable to impersonate user: uid is nil")
        ngx.exit(ngx.HTTP_INTERNAL_SERVER_ERROR)
    end

    local _uid = tonumber(uid)
    local previous = _setfsuid(_uid)
    local actual = _setfsuid(_uid)

    if actual ~= _uid then
        ngx.log(ngx.CRIT, "Unable to impersonate users")
        ngx.exit(ngx.HTTP_INTERNAL_SERVER_ERROR)
    end
end

--- Set the GID for the process
-- This is the nginx-friendly function. This should be the primary GID.
--
-- @param gid The GID for filesytem operations.
local function setgid(gid)
    if gid == nil or gid == 0 then
        ngx.log(ngx.CRIT, "Unable to impersonate group: gid is nil")
        ngx.exit(ngx.HTTP_INTERNAL_SERVER_ERROR)
    end

    if not syscall_api.setgid(tonumber(gid)) then
        ngx.log(ngx.CRIT, "Unable to set gid")
        ngx.exit(ngx.HTTP_INTERNAL_SERVER_ERROR)
    end
end

--- Init groups for a user with a given GID
-- This is the nginx-friendly function.
-- **This function requires passwd/group information
-- to be available to the host.**
--
-- @param username
-- @param gid The GID for filesytem operations.
local function initgroups(username, gid)
    if gid == nil or gid == 0 then
        ngx.log(ngx.CRIT, "Unable to initgroups: gid is nil")
        ngx.exit(ngx.HTTP_INTERNAL_SERVER_ERROR)
    end
    if not _initgroups(username, tonumber(gid)) then
        ngx.log(ngx.CRIT, "Unable init groups")
        ngx.exit(ngx.HTTP_INTERNAL_SERVER_ERROR)
    end
end

--- Set supplementary groups for a user.
-- This is the nginx-friendly function.
--
-- @param groups list of the supplementary groups for the user
local function setgroups(groups)
    _groups = {}
    for i, group in ipairs(groups) do
        if group == nil or group == 0 then
            ngx.log(ngx.CRIT, "Unable to setgroups: group is nil")
            ngx.exit(ngx.HTTP_INTERNAL_SERVER_ERROR)
        end
      _groups[i] = tonumber(group)
    end
    if not syscall_api.setgroups(_groups) then
        ngx.log(ngx.CRIT, "Unable set groups")
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
local function init_user(username, uid)
    local passwd
    if username then
        passwd = ffi.C.getpwnam(username)
    elseif uid and uid ~= 0 then
        passwd = ffi.C.getpwuid(tonumber(uid))
    end

    if passwd == nil then
        ngx.log(ngx.CRIT, "No valid username or uid")
        ngx.exit(ngx.HTTP_INTERNAL_SERVER_ERROR)
    end

    -- Could get UID and groups here from REMOTE_USER via /etc/passwd
    -- Set FSUID
    ngx.log(ngx.NOTICE, "[Impersonating UID #" .. passwd.pw_uid .. ", GID #" .. passwd.pw_gid .. "]")
    setfsuid(passwd.pw_uid)
    setgid(passwd.pw_gid)
    initgroups(passwd.pw_name, passwd.pw_gid)
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
local function set_user(uid, gid, groups)
    ngx.log(ngx.NOTICE, "[Impersonating UID #" .. uid .. ", GID #" .. gid .. "]")
    setfsuid(uid)
    setgid(gid)
    setgroups(groups)
end

local function init_user_from_uid(uid)
    return init_user(nil, uid)
end

local function init_user_from_username(username)
    return init_user(username, nil)
end

M.setfsuid = setfsuid
M.setgid = setgid
M.setgroups = setgroups
M.set_user = set_user
M.init_user = init_user
M.init_user_from_uid = init_user_from_uid
M.init_user_from_username = init_user_from_username

return M
