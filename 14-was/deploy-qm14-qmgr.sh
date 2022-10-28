#!/bin/bash
#
#  (C) Copyright IBM Corp. 2021. All Rights Reserved.
#
# SPDX-License-Identifier: Apache-2.0
#
# Not for Production use. For demo and training only.
#

# Create a private key and a self-signed certificate for the queue manager

openssl req -newkey rsa:2048 -nodes -keyout qm14.key -subj "//CN=qm14" -x509 -days 3650 -out qm14.crt

# Create a private key and a self-signed certificate for the client application

# openssl req -newkey rsa:2048 -nodes -keyout mqadmin.key -subj "//CN=mqadmin" -x509 -days 3650 -out mqadmin.crt

# Create the client JKS key store:

# First, put the key (`mqadmin.key`) and certificate (`mqadmin.crt`) into a PKCS12 file. PKCS12 is a format suitable for importing into the client key database (`mqadminkey.kdb`):

#openssl pkcs12 -export -out mqadmin.p12 -inkey mqadmin.key -in mqadmin.crt -name mqadmin -password pass:password

# Next, create mqadmin jks keystore for mq explorer
#keytool -importkeystore -deststorepass password -destkeypass password -destkeystore mqadmin-keystore.jks -deststoretype jks -srckeystore mqadmin.p12 -srcstoretype PKCS12 -srcstorepass password -alias mqadmin

# Create JKS trust store for MQ Explorer
keytool -importcert -file qm14.crt -alias qm14cert -keystore mqadmin-truststore.jks -storetype jks -storepass password -noprompt
# IVO:: import also APIS root certificate to client's JKS trust store
keytool -keystore mqadmin-truststore.jks -storetype jks -import -file APIS_root_certificate.crt -alias apisrootcert -storepass password -noprompt

# List the trust store certificate
keytool -list -keystore mqadmin-truststore.jks -storepass password


######################################################################
############### BEGIN rfhutilc.exe configuration part ################
######################################################################
# Now, we also need to package these keys and certificates to a CMS .kdb keystore/truststore, which is a formate required by rfhutil(c).exe tool
# First, create the store
runmqakm -keydb -create -db mqadmin-truststore.kdb -pw password -type cms -stash
# Add the queue manager public key to the client key database:
runmqakm -cert -add -db mqadmin-truststore.kdb -label qm14cert -file qm14.crt -format ascii -stashed
# IVO:: import also APIS root certificate to client's CMS trust store
runmqakm -cert -add -db mqadmin-truststore.kdb -label apisrootcert -file APIS_root_certificate.crt -format ascii -stashed

# Next, Add the client's certificate and key to the client key database:
# Import the PKCS12 file. The label **must be** `ibmwebspheremq<your userid>`:
# runmqakm -cert -import -target mqadmin.kdb -file mqx1.p12 -target_stashed -pw password -new_label $label

# Last Checkpoint. List the database certificates:
runmqakm -cert -list -db mqadmin-truststore.kdb -stashed

######################################################################
################# END rfhutilc.exe configuration part ################
######################################################################


# Create TLS Secret for the Queue Manager

oc create secret tls example-14-qm14-secret -n $OCP_PROJECT --key="qm14.key" --cert="qm14.crt"

# Create TLS Secret with the client's certificate

# oc create secret generic example-14-mqadmin-secret -n $OCP_PROJECT --from-file=mqadmin.crt=mqadmin.crt

# Create a config map containing MQSC commands

cat > qm14-configmap.yaml << EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: example-07-qm14-configmap
data:
  qm14.mqsc: |
    DEFINE CHANNEL(qm14CHL) CHLTYPE(SVRCONN) REPLACE TRPTYPE(TCP) SSLCAUTH(REQUIRED) SSLCIPH('ANY_TLS12_OR_HIGHER')
    ALTER AUTHINFO(SYSTEM.DEFAULT.AUTHINFO.IDPWOS) AUTHTYPE(IDPWOS) CHCKCLNT(OPTIONAL)
    SET CHLAUTH('qm14CHL') TYPE(SSLPEERMAP) SSLPEER('CN=mqadmin') USERSRC(MAP) MCAUSER('mqadmin') ACTION(ADD)
    SET AUTHREC PROFILE('SYSTEM.ADMIN.COMMAND.QUEUE')    OBJTYPE(QUEUE) PRINCIPAL('mqadmin') AUTHADD(DSP, INQ, PUT)
    SET AUTHREC PROFILE('SYSTEM.MQEXPLORER.REPLY.MODEL') OBJTYPE(QUEUE) PRINCIPAL('mqadmin') AUTHADD(DSP, INQ, GET, PUT)
    SET AUTHREC PROFILE('**') OBJTYPE(AUTHINFO) PRINCIPAL('mqadmin') AUTHADD(ALLADM, CRT)
    SET AUTHREC PROFILE('**') OBJTYPE(CHANNEL)  PRINCIPAL('mqadmin') AUTHADD(ALLADM, CRT)
    SET AUTHREC PROFILE('**') OBJTYPE(CLNTCONN) PRINCIPAL('mqadmin') AUTHADD(ALLADM, CRT)
    SET AUTHREC PROFILE('**') OBJTYPE(COMMINFO) PRINCIPAL('mqadmin') AUTHADD(ALLADM, CRT)
    SET AUTHREC PROFILE('**') OBJTYPE(LISTENER) PRINCIPAL('mqadmin') AUTHADD(ALLADM, CRT)
    SET AUTHREC PROFILE('**') OBJTYPE(NAMELIST) PRINCIPAL('mqadmin') AUTHADD(ALLADM, CRT)
    SET AUTHREC PROFILE('**') OBJTYPE(PROCESS)  PRINCIPAL('mqadmin') AUTHADD(ALLADM, CRT)
    SET AUTHREC PROFILE('**') OBJTYPE(QUEUE)    PRINCIPAL('mqadmin') AUTHADD(ALLADM, CRT, ALLMQI)
    SET AUTHREC               OBJTYPE(QMGR)     PRINCIPAL('mqadmin') AUTHADD(ALLADM, CONNECT, INQ)
    SET AUTHREC PROFILE('**') OBJTYPE(RQMNAME)  PRINCIPAL('mqadmin') AUTHADD(ALLADM, CRT)
    SET AUTHREC PROFILE('**') OBJTYPE(SERVICE)  PRINCIPAL('mqadmin') AUTHADD(ALLADM, CRT)
    SET AUTHREC PROFILE('**') OBJTYPE(TOPIC)    PRINCIPAL('mqadmin') AUTHADD(ALLADM, CRT, ALLMQI)
  qm14.ini: |-
    SSL:
      OutboundSNI=HOSTNAME
    Service:
      Name=AuthorizationService
      EntryPoints=14
      SecurityPolicy=UserExternal
EOF

oc apply -n $OCP_PROJECT -f qm14-configmap.yaml

# Create the required route for SNI

cat > qm14chl-route.yaml << EOF
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: example-07-qm14-route
spec:
  host: qm14chl.chl.mq.ibm.com
  to:
    kind: Service
    name: qm14-ibm-mq
  port:
    targetPort: 1414
  tls:
    termination: passthrough
EOF

# no need to create route (because not using channel routes) - Operator automatically generates route for hostname :: oc apply -n cp4i -f qm14chl-route.yaml

# Deploy the queue manager

cat > qm14-qmgr.yaml << EOF
apiVersion: mq.ibm.com/v1beta1
kind: QueueManager
metadata:
  name: qm14
spec:
  license:
    accept: true
    license: L-RJON-C7QG3S
    use: NonProduction
  queueManager:
    name: qm14
    ini:
      - configMap:
          name: example-07-qm14-configmap
          items:
            - qm14.ini
    mqsc:
    - configMap:
        name: example-07-qm14-configmap
        items:
        - qm14.mqsc
    storage:
      queueManager:
        type: ephemeral
  version: 9.2.5.0-r3
  web:
    enabled: false
  pki:
    keys:
      - name: example
        secret:
          secretName: example-07-qm14-secret
          items:
          - tls.key
          - tls.crt
    trust:
    - name: mqadmin
      secret:
        secretName: example-07-mqadmin-secret
        items:
          - mqadmin.crt
EOF

oc apply -n $OCP_PROJECT -f qm14-qmgr.yaml

# wait 5 minutes for queue manager to be up and running
# (shouldn't take more than 2 minutes, but just in case)
for i in {1..60}
do
  phase=`oc get qmgr -n $OCP_PROJECT qm14 -o jsonpath="{.status.phase}"`
  if [ "$phase" == "Running" ] ; then break; fi
  echo "Waiting for qm14...$i"
  oc get qmgr -n $OCP_PROJECT qm14
  sleep 5
done

if [ $phase != "Running" ]
then
   echo "*** Queue Manager qm14 is not ready ***"
   exit 1
fi

echo "Queue Manager qm14 is Running"

# Create the Client Channel Definition Table (CCDT)
# Find the queue manager host name

qmhostname=`oc get route -n $OCP_PROJECT qm14-ibm-mq-qm -o jsonpath="{.spec.host}"`
echo $qmhostname

# Test:

nslookup $qmhostname

# Create ccdt.json

cat > ccdt.json << EOF
{
    "channel":
    [
        {
            "name": "qm14CHL",
            "clientConnection":
            {
                "connection":
                [
                    {
                        "host": "$qmhostname",
                        "port": 443
                    }
                ],
                "queueManager": "qm14"
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
