#!/bin/bash

set -o errexit
set -o nounset
set -o pipefail


ARCH="linux-amd64"
CERT_DIR="/tmp/kubernetes/pki"

TMPDIR=$(mktemp -d --tmpdir kubernetes_cacert.XXXXXX)
trap 'rm -rf "${TMPDIR}"' EXIT
cd "${TMPDIR}"

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
            "kubernetes": {
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
    "CN": "kubernetes",
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

#  *.elb.amazonaws.com为ELB通配符域名,不加会造成kubelet在请求apiserver时候报证书错误
cat <<EOF > kube-apiserver.json
{
    "CN": "kubernetes",
    "hosts": [
        "localhost",
        "127.0.0.1",
        "172.31.25.244",
        "172.31.29.234",
        "172.31.21.119",
        "10.254.0.1",
        "*.elb.amazonaws.com",
        "kubernetes",
        "kubernetes.default",
        "kubernetes.default.svc",
        "kubernetes.default.svc.cluster",
        "kubernetes.default.svc.cluster.local"
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

if ! (cfssl gencert -ca=ca.pem -ca-key=ca-key.pem -config=ca-config.json -profile=kubernetes kube-apiserver.json | cfssljson -bare kube-apiserver) >/dev/null 2>&1; then
    echo "=== Failed to generate kube-apiserver certificates: Aborting ===" 1>&2
    exit 2
fi

cat <<EOF > admin.json
{
    "CN": "admin",
    "hosts": [""],
    "key": {
        "algo": "rsa",
        "size": 2048
    },
    "names": [
        {
            "C": "CN",
            "ST": "Beijing",
            "L": "Beijing",
            "O": "system:masters",
            "OU": "System"
        }
    ]
}
EOF

if ! (cfssl gencert -ca=ca.pem -ca-key=ca-key.pem -config=ca-config.json -profile=kubernetes admin.json | cfssljson -bare admin) >/dev/null 2>&1; then
    echo "=== Failed to generate admin certificates: Aborting ===" 1>&2
    exit 2
fi

cat <<EOF > kube-proxy.json
{
    "CN": "system:kube-proxy",
    "hosts": [""],
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

if ! (cfssl gencert -ca=ca.pem -ca-key=ca-key.pem -config=ca-config.json -profile=kubernetes kube-proxy.json | cfssljson -bare kube-proxy) >/dev/null 2>&1; then
    echo "=== Failed to generate kube-proxy certificates: Aborting ===" 1>&2
    exit 2
fi

mkdir -p "$CERT_DIR"

cp ./*.pem ${CERT_DIR}/