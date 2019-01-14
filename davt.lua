local ffi = require("ffi")
local syscall_api = require("syscall") -- loads ffi.C for us
local nr = require("syscall.linux.nr")

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

local function initgroups(user, gid)
    return ffi.C.initgroups(user, gid) == 0
end

local function setfsuid(id)
    return tonumber(ffi.C.syscall(nr.SYS.setfsuid, ffi.typeof("unsigned int")(id)))
end

function M.impersonate(user, uid)
    local passwd
    if user then
        passwd = ffi.C.getpwnam(user)
    elseif uid then
        passwd = ffi.C.getpwuid(uid)
    end

    if passwd == nil then
        ngx.log(ngx.CRIT, "No valid username or uid")
        ngx.exit(ngx.HTTP_INTERNAL_SERVER_ERROR)
    end

    -- Could get UID and groups here from REMOTE_USER via /etc/passwd
    -- Set FSUID
    ngx.log(ngx.NOTICE, "[Impersonating UID #" .. passwd.pw_uid .. ", GID #" .. passwd.pw_gid .. "]")
    local previous = setfsuid(passwd.pw_uid)
    local actual = setfsuid(passwd.pw_uid)

    if actual ~= passwd.pw_uid then
        ngx.log(ngx.CRIT, "Unable to impersonate users")
        ngx.exit(ngx.HTTP_INTERNAL_SERVER_ERROR)
    end

    -- Set GID
    if not syscall_api.setgid(passwd.pw_gid) then
        ngx.log(ngx.CRIT, "Unable to set gid")
        ngx.exit(ngx.HTTP_INTERNAL_SERVER_ERROR)
    end

    -- Set Supplementary Groups
    if not initgroups(passwd.pw_name, passwd.pw_gid) then
        ngx.log(ngx.CRIT, "Unable init groups" .. retval)
        ngx.exit(ngx.HTTP_INTERNAL_SERVER_ERROR)
    end
end

return M

