#!/bin/bash

set -o errexit
set -o nounset
set -o pipefail

ARCH="linux-amd64"
CERT_DIR="/tmp/kubernetes/pki/dashboard"

TMPDIR=$(mktemp -d --tmpdir dashboard_cacert.XXXXXX)
trap 'rm -rf "${TMPDIR}"' EXIT
cd "${TMPDIR}" || exit

mkdir -p bin
curl -sSL -o ./bin/cfssl "https://pkg.cfssl.org/R1.2/cfssl_$ARCH"
curl -sSL -o ./bin/cfssljson "https://pkg.cfssl.org/R1.2/cfssljson_$ARCH"
chmod +x ./bin/cfssl{,json}

export PATH="$PATH:${TMPDIR}/bin/"

cat <<EOF > ca-config.json
{
    "signing": {
        "default": {
            "expiry": "87600h"
        },
        "profiles": {
            "server": {
                "expiry": "87600h",
                "usages": [
                    "signing",
                    "key encipherment",
                    "server auth",
                    "client auth"
                ]
            }
        }
    }
}
EOF

cat <<EOF > ca-csr.json
{
    "CN": "kubernetes-dashboard",
    "key": {
        "algo": "rsa",
        "size": 2048
    },
    "names": [
        {
            "C": "CN",
            "ST": "Beijing",
            "L": "Beijing",
            "O": "k8s",
            "OU": "System"
        }
    ]
}
EOF

if ! (cfssl gencert -initca ca-csr.json | cfssljson -bare ca -) >/dev/null 2>&1; then
    echo "=== Failed to generate CA certificates: Aborting ===" 1>&2
    exit 2
fi

cat <<EOF > dashboard.json
{
    "CN": "kubernetes-dashboard",
    "hosts": [
        "*.dwnews.com"
    ],
    "key": {
        "algo": "rsa",
        "size": 2048
    },
    "names": [
        {
            "C": "CN",
            "ST": "Beijing",
            "L": "Beijing",
            "O": "k8s",
            "OU": "System"
        }
    ]
}
EOF

if ! (cfssl gencert -ca=ca.pem -ca-key=ca-key.pem -config=ca-config.json -profile=server dashboard.json | cfssljson -bare dashboard) >/dev/null 2>&1; then
    echo "=== Failed to generate server certificates: Aborting ===" 1>&2
    exit 2
fi

mkdir -p "$CERT_DIR"

cp ./*.pem ${CERT_DIR}/
