# davt

`davt` is a lua module for nginx to aid with impersonation. Its target use case is for use with 
WebDAV, so that all operations are executed _as the user in the request_. 

For every incoming request, davt enables nginx to switch the OS user (with `setfsuid`) and/or 
group IDs/supplementary group IDs (via `setfsgid`, `setgroups`, `initgroups`) to match the 
authenticated user or specific groups before performing any file opertions.

As davt enables impersonation, a few properties follow:

* The files do NOT need to be owned by an nginx service account user, nor does an ACL need to be 
modified to allow for access to an service group (for filesystems supporting ACLs). This allows 
you to transperently operate the service over existing directories.

* Ownership when creating files is preserved for the files in question. This ensures that files 
created for the user via WebDAV are also readable when the user is in a shell, for example.

## Requirements
davt requires ljsyscall. It also used the ffi library from LuaJIT.

## Deployment

davt is only compatible with Linux. davt must be ran as root. It is recommended 
that you drop all capabilities EXCEPT `CAP_SETGID` and `CAP_SETUID`, although it seems like 
`CAP_SETPCAP` may be necessary, as well as `CAP_NET_BIND_SERVICE` if you want to bind to a 
privileged port (ports 80, 443, etc...).

As davt allows impersonation, all incoming requests to davt MUST match a preset secret that the 
davt lua object is configured with. If it is desired to disable checkin, setting the secret 
explicitly to the empty string can be used, as in the following example:


```lua
local lua_davt = require("davt")
local davt = lua_davt:new({secret = ""})
```

If no secret is explicitly set, davt will set a random secret at startup, printing that secret 
out to the log. The following code will do that:

```lua
local lua_davt = require("davt")
local davt = lua_davt:new()
```
