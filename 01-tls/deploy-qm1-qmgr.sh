#!/bin/bash
#
#  (C) Copyright IBM Corp. 2021. All Rights Reserved.
#
# SPDX-License-Identifier: Apache-2.0
#
# Not for Production use. For demo and training only.
#

export OCP_PROJECT=cp4i-mq-dev
echo !!! OCP project used: $OCP_PROJECT - edit this script to fix/change!!!


# Create a private key and a self-signed certificate for the queue manager

openssl req -newkey rsa:2048 -nodes -keyout qm1.key -subj "//CN=qm1" -x509 -days 3650 -out qm1.crt

# Create JKS trust store for MQ Explorer and other java applications
keytool -importcert -file qm1.crt -alias qm1cert -keystore client-truststore.jks -storetype jks -storepass password -noprompt
# IVO:: import also APIS root certificate to client's JKS trust store
keytool -keystore client-truststore.jks -storetype jks -import -file APIS_root_certificate.crt -alias apisrootcert -storepass password -noprompt

# List the trust store certificate
keytool -list -keystore client-truststore.jks -storepass password


# Create the client key database:

runmqakm -keydb -create -db app1key.kdb -pw password -type cms -stash

# Add the queue manager public key to the client key database:

runmqakm -cert -add -db app1key.kdb -label qm1cert -file qm1.crt -format ascii -stashed
# IVO:: import also APIS root certificate to client's JKS trust store
runmqakm -cert -add -db app1key.kdb -label apisrootcert -file APIS_root_certificate.crt -format ascii -stashed

# Check. List the database certificates:

runmqakm -cert -list -db app1key.kdb -stashed

# Create TLS Secret for the Queue Manager

oc create secret tls example-01-qm1-secret -n $OCP_PROJECT --key="qm1.key" --cert="qm1.crt"

# Create a config map containing MQSC commands

cat > qm1-configmap.yaml << EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: example-01-qm1-configmap
data:
  qm1.mqsc: |
    DEFINE QLOCAL('Q1') REPLACE DEFPSIST(YES)
    DEFINE CHANNEL(QM1CHL) CHLTYPE(SVRCONN) REPLACE TRPTYPE(TCP) SSLCAUTH(OPTIONAL) SSLCIPH('ANY_TLS12_OR_HIGHER')
    SET CHLAUTH(QM1CHL) TYPE(BLOCKUSER) USERLIST('nobody') ACTION(ADD)
EOF

oc apply -n $OCP_PROJECT -f qm1-configmap.yaml

# Create the required route for SNI

cat > qm1chl-route.yaml << EOF
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: example-01-qm1-route
spec:
  host: qm1chl.chl.mq.ibm.com
  to:
    kind: Service
    name: qm1-ibm-mq
  port:
    targetPort: 1414
  tls:
    termination: passthrough
EOF

# ROUTE NOT NEEDED oc apply -n $OCP_PROJECT -f qm1chl-route.yaml

# Deploy the queue manager

cat > qm1-qmgr.yaml << EOF
apiVersion: mq.ibm.com/v1beta1
kind: QueueManager
metadata:
  name: qm1
spec:
  license:
    accept: true
    license: L-RJON-CD3JKX
    use: NonProduction
  queueManager:
    name: QM1
    mqsc:
    - configMap:
        name: example-01-qm1-configmap
        items:
        - qm1.mqsc
    storage:
      queueManager:
        type: ephemeral
    resources:
      limits:
        cpu: '1'
        memory: 512Mi
      requests:
        cpu: 100m
        memory: 512Mi
  template:
    pod:
      containers:
        - env:
            - name: MQSNOAUT
              value: 'yes'
          name: qmgr
  version: 9.3.0.1-r2
  web:
    enabled: true
  pki:
    keys:
      - name: example
        secret:
          secretName: example-01-qm1-secret
          items:
          - tls.key
          - tls.crt
EOF

oc apply -n $OCP_PROJECT -f qm1-qmgr.yaml

# wait 5 minutes for queue manager to be up and running
# (shouldn't take more than 2 minutes, but just in case)
for i in {1..60}
do
  phase=`oc get qmgr -n $OCP_PROJECT qm1 -o jsonpath="{.status.phase}"`
  if [ "$phase" == "Running" ] ; then break; fi
  echo "Waiting for qm1...$i"
  oc get qmgr -n $OCP_PROJECT qm1
  sleep 5
done

if [ $phase == Running ]
   then echo Queue Manager qm1 is ready;
   break;
fi

# Create the Client Channel Definition Table (CCDT)
# Find the queue manager host name

qmhostname=`oc get route -n $OCP_PROJECT qm1-ibm-mq-qm -o jsonpath="{.spec.host}"`
echo $qmhostname

# Test:

curl --insecure https://$qmhostname

# Create ccdt.json

cat > ccdt.json << EOF
{
    "channel":
    [
        {
            "name": "QM1CHL",
            "clientConnection":
            {
                "connection":
                [
                    {
                        "host": "$qmhostname",
                        "port": 443
                    }
                ],
                "queueManager": "QM1"
            },
            "transmissionSecurity":
            {
              "cipherSpecification": "ANY_TLS12_OR_HIGHER"
            },
            "type": "clientConnection"
        }
   ]
}
EOF

exit 1
