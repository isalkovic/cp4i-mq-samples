#!/bin/bash
#
#  (C) Copyright IBM Corp. 2021. All Rights Reserved.
#
# SPDX-License-Identifier: Apache-2.0
#
# Not for Production use. For demo and training only.
#

# Create a private key and a self-signed certificate for the queue manager

openssl req -newkey rsa:2048 -nodes -keyout qm6.key -subj "/CN=qm6" -x509 -days 3650 -out qm6.crt

# Set up the first client ("app1")
# Create a private key and a self-signed certificate for the client application

openssl req -newkey rsa:2048 -nodes -keyout app1.key -subj "/CN=app1" -x509 -days 3650 -out app1.crt

# Create the client key database:

runmqakm -keydb -create -db app1key.kdb -pw password -type cms -stash

# Add the queue manager public key to the client key database:

runmqakm -cert -add -db app1key.kdb -label qm6cert -file qm6.crt -format ascii -stashed

# Add the client's certificate and key to the client key database:

# First, put the key (`app1.key`) and certificate (`app1.crt`) into a PKCS12 file. PKCS12 is a format suitable for importing into the client key database (`app1key.kdb`):

openssl pkcs12 -export -out app1.p12 -inkey app1.key -in app1.crt -password pass:password

# Next, import the PKCS12 file. The label **must be** `ibmwebspheremq<your userid>`:

label=ibmwebspheremq`id -u -n`
runmqakm -cert -import -target app1key.kdb -file app1.p12 -target_stashed -pw password -new_label $label

# Check. List the database certificates:

runmqakm -cert -list -db app1key.kdb -stashed

# Set up the second client ("app2")
# Create a private key and a self-signed certificate for the client application

openssl req -newkey rsa:2048 -nodes -keyout app2.key -subj "/CN=app2" -x509 -days 3650 -out app2.crt

# Create the client key database:

runmqakm -keydb -create -db app2key.kdb -pw password -type cms -stash

# Add the queue manager public key to the client key database:

runmqakm -cert -add -db app2key.kdb -label qm6cert -file qm6.crt -format ascii -stashed

# Add the client's certificate and key to the client key database:

# First, put the key (`app2.key`) and certificate (`app2.crt`) into a PKCS12 file. PKCS12 is a format suitable for importing into the client key database (`app2key.kdb`):

openssl pkcs12 -export -out app2.p12 -inkey app2.key -in app2.crt -password pass:password

# Next, import the PKCS12 file. The label **must be** `ibmwebspheremq<your userid>`:

label=ibmwebspheremq`id -u -n`
runmqakm -cert -import -target app2key.kdb -file app2.p12 -target_stashed -pw password -new_label $label

# Check. List the database certificates:

runmqakm -cert -list -db app2key.kdb -stashed

# Create TLS Secret for the Queue Manager

oc create secret tls example-06-qm6-secret -n cp4i --key="qm6.key" --cert="qm6.crt"

# Create TLS Secret with the client's certificate ("app1")

oc create secret generic example-06-app1-secret -n cp4i --from-file=app1.crt=app1.crt

# Create TLS Secret with the client's certificate ("app2")

oc create secret generic example-06-app2-secret -n cp4i --from-file=app2.crt=app2.crt

# Create a config map containing MQSC commands and qm.ini

cat > qm6-configmap.yaml << EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: example-06-qm6-configmap
data:
  qm6.mqsc: |
    DEFINE QLOCAL('Q1') REPLACE DEFPSIST(YES) 
    DEFINE CHANNEL(QM6CHL) CHLTYPE(SVRCONN) REPLACE TRPTYPE(TCP) SSLCAUTH(REQUIRED) SSLCIPH('ANY_TLS12_OR_HIGHER')
    ALTER AUTHINFO(SYSTEM.DEFAULT.AUTHINFO.IDPWOS) AUTHTYPE(IDPWOS) CHCKCLNT(OPTIONAL)
    SET CHLAUTH('QM6CHL') TYPE(SSLPEERMAP) SSLPEER('CN=app1') USERSRC(MAP) MCAUSER('app1') ACTION(REPLACE)
    SET AUTHREC PRINCIPAL('app1') OBJTYPE(QMGR) AUTHADD(CONNECT,INQ)
    SET AUTHREC PROFILE('Q1') PRINCIPAL('app1') OBJTYPE(QUEUE) AUTHADD(INQ,PUT)
    SET CHLAUTH('QM6CHL') TYPE(SSLPEERMAP) SSLPEER('CN=app2') USERSRC(MAP) MCAUSER('app2') ACTION(REPLACE)
    SET AUTHREC PRINCIPAL('app2') OBJTYPE(QMGR) AUTHADD(CONNECT,INQ)
    SET AUTHREC PROFILE('Q1') PRINCIPAL('app2') OBJTYPE(QUEUE) AUTHADD(BROWSE,GET,INQ)
    REFRESH SECURITY
  qm6.ini: |-
    Service:
      Name=AuthorizationService
      EntryPoints=14
      SecurityPolicy=UserExternal
EOF

oc apply -n cp4i -f qm6-configmap.yaml

# Create the required route for SNI

cat > qm6chl-route.yaml << EOF
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: example-06-qm6-route
spec:
  host: qm6chl.chl.mq.ibm.com
  to:
    kind: Service
    name: qm6-ibm-mq
  port:
    targetPort: 1414
  tls:
    termination: passthrough
EOF

oc apply -n cp4i -f qm6chl-route.yaml

# Deploy the queue manager

cat > qm6-qmgr.yaml << EOF
apiVersion: mq.ibm.com/v1beta1
kind: QueueManager
metadata:
  name: qm6
spec:
  license:
    accept: true
    license: L-RJON-CD3JKX
    use: NonProduction
  queueManager:
    name: QM6
    ini:
      - configMap:
          name: example-06-qm6-configmap
          items:
            - qm6.ini
    mqsc:
    - configMap:
        name: example-06-qm6-configmap
        items:
        - qm6.mqsc
    availability:
      type: NativeHA
    storage:
      defaultClass: ibmc-block-gold
      persistedData:
        enabled: false
      queueManager:
        size: 2Gi
        type: persistent-claim
      recoveryLogs:
        enabled: false
  version: 9.3.0.0-r1
  web:
    enabled: false
  pki:
    keys:
      - name: example
        secret:
          secretName: example-06-qm6-secret
          items: 
          - tls.key
          - tls.crt
    trust:
    - name: app1
      secret:
        secretName: example-06-app1-secret
        items:
          - app1.crt
    - name: app2
      secret:
        secretName: example-06-app2-secret
        items:
          - app2.crt
EOF

oc apply -n cp4i -f qm6-qmgr.yaml

# wait 5 minutes for queue manager to be up and running
# (shouldn't take more than 2 minutes, but just in case)
for i in {1..60}
do
  phase=`oc get qmgr -n cp4i qm6 -o jsonpath="{.status.phase}"`
  if [ "$phase" == "Running" ] ; then break; fi
  echo "Waiting for qm6...$i"
  oc get qmgr -n cp4i qm6
  sleep 5
done

if [ $phase == Running ]
   then echo Queue Manager qm6 is ready; 
   exit; 
fi

echo "*** Queue Manager qm6 is not ready ***"
exit 1
