# davt

davt is a lua module for nginx to aid with impersonation. It's target use case is for use with 
WebDAV, so that all operations are executed _as the user in the request_. 

For every incoming request, davt enables nginx to switch the OS user (e.g. setfsuid) and/or group 
IDs/supplementary group IDs (via setfsgid, setgroups, initgroups) to match the authenticated user 
or specific groups before performing any file opertions.

As davt enables impersonation, a few properties follow:

* The files do NOT need to be owned by an nginx service account user, nor does an ACL need to be 
modified to allow for access to an service group (for filesystems supporting ACLs). This allows 
you to transperently operate the service over existing directories.

* Ownership when creating files is preserved for the files in question. This ensures that files 
created for the user via WebDAV are also readable when the user is in a shell, for example.

## Requirements
davt requires ljsyscall. It also used the ffi from LuaJIT.

## Deployment

davt is only compatible with linux. davt, as it seems now, must be ran as root. It is recommended 
that you drop all capabilities EXCEPT CAP_SETGID and CAPS_SETUID, although it seems like 
CAP_SETPCAP may be necessary, as well as CAP_NET_BIND_SERVICE if you want to bind to a privileged 
port (ports 80, 443, etc...).

As davt allows impersonation, all incoming requests to davt MUST match a preset secret that the 
davt lua object is configured with. This secret may be an empty string, which *DISABLES* this 
check, but it must still be explicitly set. If no secret is set, davt will set a random secret at 
startup and print that out to the log.
