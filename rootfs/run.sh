#!/bin/sh


# Capabilties Kept
# cap_setgid,cap_setuid,cap_net_bind_service
#
#
# Dropped capabilites:
# Might Need:
# cap_net_raw,cap_chown,cap_fsetid,cap_setpcap
#
# Probably don't want:
# cap_kill,cap_sys_chroot,cap_mknod,cap_audit_write,cap_setfcap+eip

capsh --caps="cap_setpcap+eip cap_setgid+eip cap_setuid+eip cap_net_bind_service+eip" \
  --drop="cap_chown,cap_dac_override,cap_fowner,cap_fsetid,cap_kill,cap_setpcap,cap_sys_chroot,cap_mknod,cap_audit_write,cap_setfcap" \
  -- -c 'nginx -g "daemon off;"'
