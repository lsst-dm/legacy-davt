#!/bin/bash

b64="base64 -w0"
uname | grep -i darwin > /dev/null
is_darwin_rc=$?

if [[ $is_darwin_rc -eq 0 ]]; then
    b64="base64"
fi

echo "Hostname:"
read HOSTNAME

echo "Kubernetes Namespace:"
read NAMESPACE

echo 'Mounts (in JSON, e.g. {"/lsst/datasets": "/datasets", "/lsst/jhome": "/user"}):'
echo "The value is the export. Values are exposed under /api/dav, e.g. /api/dav/datasets, /api/dav/user"
read MOUNTS

mkdir ${NAMESPACE}

cat <<EOF > ${NAMESPACE}/data.yml
HOSTNAME: ${HOSTNAME} 
NAMESPACE: ${NAMESPACE} 
MOUNTS: ${MOUNTS}
EOF

echo "Rendering Templates"
bash ./render ${NAMESPACE}
