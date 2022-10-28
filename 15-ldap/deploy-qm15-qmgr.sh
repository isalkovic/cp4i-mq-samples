#!/bin/bash
#
#  (C) Copyright IBM Corp. 2021. All Rights Reserved.
#
# SPDX-License-Identifier: Apache-2.0
#
# Not for Production use. For demo and training only.
#

# configure default Openshift project to use - change this value to the project name applicable to your use case
export OCP_PROJECT=cp4i-mq-dev
echo !!! OCP project used: $OCP_PROJECT - edit this script to fix/change!!!

# Create a private key and a self-signed certificate for the queue manager
openssl req -newkey rsa:2048 -nodes -keyout qm15.key -subj "//CN=qm15" -x509 -days 3650 -out qm15.crt

# Create JKS trust store for MQ Explorer
keytool -importcert -file qm15.crt -alias qm15cert -keystore mqx1-truststore.jks -storetype jks -storepass password -noprompt
# IVO:: import also APIS root certificate to client's JKS trust store
keytool -keystore mqx1-truststore.jks -storetype jks -import -file APIS_root_certificate.crt -alias apisrootcert -storepass password -noprompt

# List the trust store certificate
keytool -list -keystore mqx1-truststore.jks -storepass password

# Create the client key database:
runmqakm -keydb -create -db app1key.kdb -pw password -type cms -stash

# Add the queue manager public key to the client key database:
runmqakm -cert -add -db app1key.kdb -label qm15cert -file qm15.crt -format ascii -stashed

# Check. List the database certificates:
runmqakm -cert -list -db app1key.kdb -stashed

# Create TLS Secret for the Queue Manager
oc create secret tls example-15-qm15-secret -n $OCP_PROJECT --key="qm15.key" --cert="qm15.crt"


# Create a config map containing MQSC commands

cat > qm15-configmap.yaml << EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: example-15-qm15-configmap
data:
  qm15.mqsc: |
    DEFINE AUTHINFO(IVOQM.IDPW.LDAP) AUTHTYPE(IDPWLDAP) CONNAME('ldap01hz.razvoj.gzaop.local(33389)') SHORTUSR('uid') ADOPTCTX(YES) AUTHORMD(SEARCHUSR) BASEDNG('ou=groups,ou=applications,serialNumber=18683136487-CURH,o=gov,C=HR') BASEDNU('ou=users,ou=applications,serialNumber=18683136487-CURH,o=gov,C=HR') CHCKCLNT(OPTIONAL) CHCKLOCL(NONE) CLASSGRP('accessGroup') CLASSUSR('inetOrgPerson') FINDGRP('member') GRPFIELD('cn') LDAPPWD('curhaarazvoj2009') LDAPUSER('uid=CURH_reader,ou=AAA-users,ou=users,o=apis-it,c=HR') NESTGRP(YES) SECCOMM(NO) USRFIELD('uid')
    ALTER QMGR CONNAUTH(IVOQM.IDPW.LDAP)
    DEFINE QLOCAL('TEST') REPLACE DEFPSIST(YES)
    DEFINE CHANNEL(QM15CHL) CHLTYPE(SVRCONN) REPLACE TRPTYPE(TCP) SSLCAUTH(OPTIONAL) SSLCIPH('ECDHE_RSA_AES_128_CBC_SHA256')
    SET CHLAUTH('QM15CHL') TYPE(ADDRESSMAP) ADDRESS('*') USERSRC(CHANNEL) DESCR('sve adrese, user sa kanala, obavezno user i pass provjera') CHCKCLNT(REQUIRED) ACTION(ADD)
    refresh security
    SET AUTHREC PRINCIPAL('dudo') OBJTYPE(QMGR) AUTHADD(CONNECT,INQ)
    SET AUTHREC PROFILE('TEST') PRINCIPAL('dudo') OBJTYPE(QUEUE) AUTHADD(BROWSE,GET,INQ,PUT)
    refresh security
    DEFINE CHANNEL(QM1CHL) CHLTYPE(SVRCONN) REPLACE TRPTYPE(TCP) SSLCAUTH(OPTIONAL) SSLCIPH('ECDHE_RSA_AES_128_CBC_SHA256')
    SET CHLAUTH(QM1CHL) TYPE(BLOCKUSER) USERLIST('nobody') ACTION(ADD)
  qm15.ini: |-
    Service:
      Name=AuthorizationService
      EntryPoints=14
      SecurityPolicy=UserExternal
    SSL:
      OutboundSNI=HOSTNAME
EOF

oc apply -n $OCP_PROJECT -f qm15-configmap.yaml

# Create the required route for SNI

cat > qm15chl-route.yaml << EOF
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: example-15-qm15-route
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

# oc apply -n $OCP_PROJECT -f qm15chl-route.yaml

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
          name: example-15-qm15-configmap
          items:
            - qm15.ini
    mqsc:
    - configMap:
        name: example-15-qm15-configmap
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
        cpu: 100m
        memory: 512Mi
  version: 9.2.5.0-r3
  web:
    enabled: true
  pki:
    keys:
      - name: example
        secret:
          secretName: example-15-qm15-secret
          items:
          - tls.key
          - tls.crt
EOF

oc apply -n $OCP_PROJECT -f qm15-qmgr.yaml

# wait 5 minutes for queue manager to be up and running
# (shouldn't take more than 2 minutes, but just in case)
for i in {1..60}
do
  phase=`oc get qmgr -n $OCP_PROJECT qm15 -o jsonpath="{.status.phase}"`
  if [ "$phase" == "Running" ] ; then break; fi
  echo "Waiting for qm15...$i"
  oc get qmgr -n $OCP_PROJECT qm15
  sleep 5
done

if [ $phase != Running ]
   then echo "***Queue Manager qm15 is not ready ***";
   exit 1;
fi

echo "*** Queue Manager qm15 is ready ***"

# Create the Client Channel Definition Table (CCDT)
# Find the queue manager host name

qmhostname=`oc get route -n $OCP_PROJECT qm15-ibm-mq-qm -o jsonpath="{.spec.host}"`
echo $qmhostname

# Test:

nslookup $qmhostname

# Create ccdt.json

cat > ccdt.json << EOF
{
    "channel":
    [
        {
            "name": "QM15CHL",
            "clientConnection":
            {
                "connection":
                [
                    {
                        "host": "$qmhostname",
                        "port": 443
                    }
                ],
                "queueManager": "QM15"
            },
            "transmissionSecurity":
            {
              "cipherSpecification": "ECDHE_RSA_AES_128_CBC_SHA256"
            },
            "type": "clientConnection"
        }
   ]
}
EOF
