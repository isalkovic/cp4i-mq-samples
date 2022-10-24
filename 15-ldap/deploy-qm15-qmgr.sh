#!/bin/bash
#
#  (C) Copyright IBM Corp. 2021. All Rights Reserved.
#
# SPDX-License-Identifier: Apache-2.0
#
# Not for Production use. For demo and training only.
#

# Create a private key and a self-signed certificate for the queue manager

openssl req -newkey rsa:2048 -nodes -keyout qm15.key -subj "//CN=qm15" -x509 -days 3650 -out qm15.crt

# Create a private key and a self-signed certificate for the client application

openssl req -newkey rsa:2048 -nodes -keyout app1.key -subj "//CN=app1" -x509 -days 3650 -out app1.crt

# Create the client key database:

runmqakm -keydb -create -db app1key.kdb -pw password -type cms -stash

# Add the queue manager public key to the client key database:

runmqakm -cert -add -db app1key.kdb -label qm15cert -file qm15.crt -format ascii -stashed

# Add the client's certificate and key to the client key database:

# First, put the key (`app1.key`) and certificate (`app1.crt`) into a PKCS12 file. PKCS12 is a format suitable for importing into the client key database (`app1key.kdb`):

openssl pkcs12 -export -out app1.p12 -inkey app1.key -in app1.crt -password pass:password

# Next, import the PKCS12 file. The label **must be** `ibmwebspheremq<your userid>`:

label=ibmwebspheremq`id -u -n`
runmqakm -cert -import -target app1key.kdb -file app1.p12 -target_stashed -pw password -new_label $label

# Check. List the database certificates:

runmqakm -cert -list -db app1key.kdb -stashed

# Create TLS Secret for the Queue Manager

oc create secret tls example-03-qm15-secret -n cp4i-mq-poc --key="qm15.key" --cert="qm15.crt"

# Create TLS Secret with the client's certificate

oc create secret generic example-03-app1-secret -n cp4i-mq-poc --from-file=app1.crt=app1.crt

# Create a config map containing MQSC commands

cat > qm15-configmap.yaml << EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: example-03-qm15-configmap
data:
  qm15.mqsc: |
    DEFINE AUTHINFO(IVOQM.IDPW.LDAP) AUTHTYPE(IDPWLDAP) CONNAME('10.193.8.182(389)') SHORTUSR('cn') ADOPTCTX(YES) AUTHORMD(SEARCHUSR) BASEDNG('dc=maxcrc,dc=com') BASEDNU('ou=People,dc=maxcrc,dc=com') CHCKCLNT(OPTIONAL) CHCKLOCL(NONE) CLASSGRP('organizationalUnit') CLASSUSR('person') FINDGRP('memberOf') GRPFIELD('ou') LDAPPWD('secret') LDAPUSER('cn=Manager,dc=maxcrc,dc=com') NESTGRP(YES) SECCOMM(NO) USRFIELD('cn')
    ALTER QMGR CONNAUTH(IVOQM.IDPW.LDAP)
    DEFINE QLOCAL('TEST') REPLACE DEFPSIST(YES)
    DEFINE CHANNEL(QM15CHL) CHLTYPE(SVRCONN) REPLACE TRPTYPE(TCP)
    SET CHLAUTH('QM15CHL') TYPE(ADDRESSMAP) ADDRESS('*') USERSRC(CHANNEL) DESCR('sve adrese, user sa kanala, obavezno user i pass provjera') CHCKCLNT(REQUIRED) ACTION(ADD)
    SET AUTHREC PRINCIPAL('ivotestuser') OBJTYPE(QMGR) AUTHADD(CONNECT,INQ)
    SET AUTHREC PROFILE('TEST') PRINCIPAL('ivotestuser') OBJTYPE(QUEUE) AUTHADD(BROWSE,GET,INQ,PUT)
  qm15.ini: |-
    Service:
      Name=AuthorizationService
      EntryPoints=14
      SecurityPolicy=UserExternal
    SSL:
      OutboundSNI=HOSTNAME
EOF

oc apply -n cp4i-mq-poc -f qm15-configmap.yaml

# Create the required route for SNI

cat > qm15chl-route.yaml << EOF
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: example-03-qm15-route
spec:
  host: qm15chl.chl.mq.ibm.com
  to:
    kind: Service
    name: qm15-ibm-mq
  port:
    targetPort: 1414
  tls:
    termination: passthrough
EOF

# oc apply -n cp4i-mq-poc -f qm15chl-route.yaml

# Deploy the queue manager

cat > qm15-qmgr.yaml << EOF
apiVersion: mq.ibm.com/v1beta1
kind: QueueManager
metadata:
  name: qm15
spec:
  license:
    accept: true
    license: L-RJON-C7QG3S
    use: NonProduction
  queueManager:
    name: QM15
    ini:
      - configMap:
          name: example-03-qm15-configmap
          items:
            - qm15.ini
    mqsc:
    - configMap:
        name: example-03-qm15-configmap
        items:
        - qm15.mqsc
    storage:
      queueManager:
        type: ephemeral
    resources:
      limits:
        cpu: '1'
        memory: 512Mi
      requests:
        cpu: 300m
        memory: 512Mi
  version: 9.2.5.0-r3
  web:
    enabled: false
  pki:
    keys:
      - name: example
        secret:
          secretName: example-03-qm15-secret
          items:
          - tls.key
          - tls.crt
    trust:
    - name: app1
      secret:
        secretName: example-03-app1-secret
        items:
          - app1.crt
EOF

oc apply -n cp4i-mq-poc -f qm15-qmgr.yaml

# wait 5 minutes for queue manager to be up and running
# (shouldn't take more than 2 minutes, but just in case)
for i in {1..60}
do
  phase=`oc get qmgr -n cp4i-mq-poc qm15 -o jsonpath="{.status.phase}"`
  if [ "$phase" == "Running" ] ; then break; fi
  echo "Waiting for qm15...$i"
  oc get qmgr -n cp4i-mq-poc qm15
  sleep 5
done

if [ $phase == Running ]
   then echo Queue Manager qm15 is ready;
   exit;
fi

echo "*** Queue Manager qm15 is not ready ***"
exit 1
