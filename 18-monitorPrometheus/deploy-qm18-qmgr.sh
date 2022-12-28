#!/bin/bash
#
#  (C) Copyright IBM Corp. 2021. All Rights Reserved.
#
# SPDX-License-Identifier: Apache-2.0
#
# Not for Production use. For demo and training only.
#

export OCP_PROJECT=cp4i-mq-poc
echo !!! OCP project used: $OCP_PROJECT - edit this script to fix/change!!!


# Create a private key and a self-signed certificate for the queue manager

openssl req -newkey rsa:2048 -nodes -keyout qm18.key -subj "//CN=qm18" -x509 -days 3650 -out qm18.crt

# Create JKS trust store for MQ Explorer and other java applications
keytool -importcert -file qm18.crt -alias qm18cert -keystore client-truststore.jks -storetype jks -storepass password -noprompt
# IVO:: import also APIS root certificate to client's JKS trust store
keytool -keystore client-truststore.jks -storetype jks -import -file APIS_root_certificate.crt -alias apisrootcert -storepass password -noprompt

# List the trust store certificate
keytool -list -keystore client-truststore.jks -storepass password


# Create the client key database:

runmqakm -keydb -create -db app1key.kdb -pw password -type cms -stash

# Add the queue manager public key to the client key database:

runmqakm -cert -add -db app1key.kdb -label qm18cert -file qm18.crt -format ascii -stashed
# IVO:: import also APIS root certificate to client's JKS trust store
runmqakm -cert -add -db app1key.kdb -label apisrootcert -file APIS_root_certificate.crt -format ascii -stashed

# Check. List the database certificates:

runmqakm -cert -list -db app1key.kdb -stashed

# Create TLS Secret for the Queue Manager

oc create secret tls example-18-qm18-secret -n $OCP_PROJECT --key="qm18.key" --cert="qm18.crt"

# Create a config map containing MQSC commands

cat > qm18-configmap.yaml << EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: example-18-qm18-configmap
data:
  qm18.mqsc: |
    DEFINE QLOCAL('Q1') REPLACE DEFPSIST(YES)
    DEFINE QLOCAL('Q2') REPLACE DEFPSIST(YES)
    DEFINE QLOCAL('Q3') REPLACE DEFPSIST(YES)
    DEFINE CHANNEL(QM18CHL) CHLTYPE(SVRCONN) REPLACE TRPTYPE(TCP)
    SET CHLAUTH(QM18CHL) TYPE(BLOCKUSER) USERLIST('nobody') ACTION(ADD)
EOF

oc apply -n $OCP_PROJECT -f qm18-configmap.yaml

# Create the required route for SNI

cat > qm18chl-route.yaml << EOF
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: example-18-qm18-route
spec:
  host: qm18chl.chl.mq.ibm.com
  to:
    kind: Service
    name: qm18-ibm-mq
  port:
    targetPort: 1414
  tls:
    termination: passthrough
EOF

# ROUTE NOT NEEDED oc apply -n $OCP_PROJECT -f qm18chl-route.yaml

# Deploy the queue manager

cat > qm18-qmgr.yaml << EOF
apiVersion: mq.ibm.com/v1beta1
kind: QueueManager
metadata:
  name: qm18
spec:
  license:
    accept: true
    license: L-RJON-CD3JKX
    use: NonProduction
  queueManager:
    name: QM18
    mqsc:
    - configMap:
        name: example-18-qm18-configmap
        items:
        - qm18.mqsc
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
          secretName: example-18-qm18-secret
          items:
          - tls.key
          - tls.crt
EOF

oc apply -n $OCP_PROJECT -f qm18-qmgr.yaml

# wait 5 minutes for queue manager to be up and running
# (shouldn't take more than 2 minutes, but just in case)
for i in {1..60}
do
  phase=`oc get qmgr -n $OCP_PROJECT qm18 -o jsonpath="{.status.phase}"`
  if [ "$phase" == "Running" ] ; then break; fi
  echo "Waiting for qm18...$i"
  oc get qmgr -n $OCP_PROJECT qm18
  sleep 5
done

if [ $phase == Running ]
   then echo Queue Manager qm18 is ready;
   exit;
fi

echo "*** Queue Manager qm18 is not ready ***"

# Create the Client Channel Definition Table (CCDT)
# Find the queue manager host name

qmhostname=`oc get route -n $OCP_PROJECT qm18-ibm-mq-qm -o jsonpath="{.spec.host}"`
echo $qmhostname

# Test:

nslookup $qmhostname

# Create ccdt.json

cat > ccdt.json << EOF
{
    "channel":
    [
        {
            "name": "QM18CHL",
            "clientConnection":
            {
                "connection":
                [
                    {
                        "host": "$qmhostname",
                        "port": 443
                    }
                ],
                "queueManager": "QM18"
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
