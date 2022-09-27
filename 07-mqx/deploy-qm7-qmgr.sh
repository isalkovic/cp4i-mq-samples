#!/bin/bash
#
#  (C) Copyright IBM Corp. 2021. All Rights Reserved.
#
# SPDX-License-Identifier: Apache-2.0
#
# Not for Production use. For demo and training only.
#

# configure default Openshift project to use - change this value to the project name applicable to your use case
export OCP_PROJECT=cp4i-mq-poc
echo $OCP_PROJECT

# Create a private key and a self-signed certificate for the queue manager
openssl req -newkey rsa:2048 -nodes -keyout qm7.key -subj "//CN=qm7" -x509 -days 3650 -out qm7.crt

# Create a private key and a self-signed certificate for the client application
openssl req -newkey rsa:2048 -nodes -keyout mqx1.key -subj "//CN=mqx1" -x509 -days 3650 -out mqx1.crt

# Create the client JKS key store:
# First, put the key (`mqx1.key`) and certificate (`mqx1.crt`) into a PKCS12 file. PKCS12 is a format suitable for importing into the client key database (`mqx1key.kdb`):
openssl pkcs12 -export -out mqx1.p12 -inkey mqx1.key -in mqx1.crt -name mqx1 -password pass:password

# Next, create mqx1 jks keystore , format required by MQ Explorer
keytool -importkeystore -deststorepass password -destkeypass password -destkeystore mqx1-keystore.jks -deststoretype jks -srckeystore mqx1.p12 -srcstoretype PKCS12 -srcstorepass password -alias mqx1

# Create JKS trust store for MQ Explorer
keytool -importcert -file qm7.crt -alias qm7cert -keystore mqx1-truststore.jks -storetype jks -storepass password -noprompt
# IVO:: import also APIS root certificate to client's JKS trust store
keytool -keystore mqx1-truststore.jks -storetype jks -import -file APIS_root_certificate.crt -alias apisrootcert -storepass password -noprompt

# List the trust store certificate
keytool -list -keystore mqx1-truststore.jks -storepass password

# List the key store certificate
keytool -list -keystore mqx1-keystore.jks -alias mqx1 -storepass password

######################################################################
############### BEGIN rfhutilc.exe configuration part ################
######################################################################
# Now, we also need to package these keys and certificates to a CMS .kdb keystore/truststore, which is a formate required by rfhutil(c).exe tool
# First, create the store
runmqakm -keydb -create -db rfhutil_allin1_store.kdb -pw password -type cms -stash
# Add the queue manager public key to the client key database:
runmqakm -cert -add -db rfhutil_allin1_store.kdb -label qm1cert -file qm7.crt -format ascii -stashed
# IVO:: import also APIS root certificate to client's CMS trust store
runmqakm -cert -add -db rfhutil_allin1_store.kdb -label apisrootcert -file APIS_root_certificate.crt -format ascii -stashed

# Next, Add the client's certificate and key to the client key database:
# Import the PKCS12 file. The label **must be** `ibmwebspheremq<your userid>`:
label=ibmwebspheremq`id -u -n`
runmqakm -cert -import -target rfhutil_allin1_store.kdb -file mqx1.p12 -target_stashed -pw password -new_label $label

# Last Checkpoint. List the database certificates:
runmqakm -cert -list -db rfhutil_allin1_store.kdb -stashed

######################################################################
################# END rfhutilc.exe configuration part ################
######################################################################

# Create TLS Secret for the Queue Manager
oc create secret tls example-07-qm7-secret -n $OCP_PROJECT --key="qm7.key" --cert="qm7.crt"

# Create TLS Secret with the client's certificate
oc create secret generic example-07-mqx1-secret -n $OCP_PROJECT --from-file=mqx1.crt=mqx1.crt

# Create a config map containing MQSC commands
cat > qm7-configmap.yaml << EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: example-07-qm7-configmap
data:
  qm7.mqsc: |
    DEFINE QLOCAL(TEST)
    DEFINE CHANNEL(QM7CHL) CHLTYPE(SVRCONN) REPLACE TRPTYPE(TCP) SSLCAUTH(REQUIRED) SSLCIPH('ANY_TLS12_OR_HIGHER')
    ALTER AUTHINFO(SYSTEM.DEFAULT.AUTHINFO.IDPWOS) AUTHTYPE(IDPWOS) CHCKCLNT(OPTIONAL)
    SET CHLAUTH('QM7CHL') TYPE(SSLPEERMAP) SSLPEER('CN=mqx1') USERSRC(MAP) MCAUSER('mqx1') ACTION(ADD)
    SET AUTHREC PROFILE('SYSTEM.ADMIN.COMMAND.QUEUE')    OBJTYPE(QUEUE) PRINCIPAL('mqx1') AUTHADD(DSP, INQ, PUT)
    SET AUTHREC PROFILE('SYSTEM.MQEXPLORER.REPLY.MODEL') OBJTYPE(QUEUE) PRINCIPAL('mqx1') AUTHADD(DSP, INQ, GET, PUT)
    SET AUTHREC PROFILE('**') OBJTYPE(AUTHINFO) PRINCIPAL('mqx1') AUTHADD(ALLADM, CRT)
    SET AUTHREC PROFILE('**') OBJTYPE(CHANNEL)  PRINCIPAL('mqx1') AUTHADD(ALLADM, CRT)
    SET AUTHREC PROFILE('**') OBJTYPE(CLNTCONN) PRINCIPAL('mqx1') AUTHADD(ALLADM, CRT)
    SET AUTHREC PROFILE('**') OBJTYPE(COMMINFO) PRINCIPAL('mqx1') AUTHADD(ALLADM, CRT)
    SET AUTHREC PROFILE('**') OBJTYPE(LISTENER) PRINCIPAL('mqx1') AUTHADD(ALLADM, CRT)
    SET AUTHREC PROFILE('**') OBJTYPE(NAMELIST) PRINCIPAL('mqx1') AUTHADD(ALLADM, CRT)
    SET AUTHREC PROFILE('**') OBJTYPE(PROCESS)  PRINCIPAL('mqx1') AUTHADD(ALLADM, CRT)
    SET AUTHREC PROFILE('**') OBJTYPE(QUEUE)    PRINCIPAL('mqx1') AUTHADD(ALLADM, CRT, ALLMQI)
    SET AUTHREC               OBJTYPE(QMGR)     PRINCIPAL('mqx1') AUTHADD(ALLADM, CONNECT, INQ)
    SET AUTHREC PROFILE('**') OBJTYPE(RQMNAME)  PRINCIPAL('mqx1') AUTHADD(ALLADM, CRT)
    SET AUTHREC PROFILE('**') OBJTYPE(SERVICE)  PRINCIPAL('mqx1') AUTHADD(ALLADM, CRT)
    SET AUTHREC PROFILE('**') OBJTYPE(TOPIC)    PRINCIPAL('mqx1') AUTHADD(ALLADM, CRT, ALLMQI)
  qm7.ini: |-
    SSL:
      OutboundSNI=HOSTNAME
    Service:
      Name=AuthorizationService
      EntryPoints=14
      SecurityPolicy=UserExternal
EOF

oc apply -n $OCP_PROJECT -f qm7-configmap.yaml

# Create the required route for SNI
cat > qm7chl-route.yaml << EOF
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: example-07-qm7-route
spec:
  host: qm7chl.chl.mq.ibm.com
  to:
    kind: Service
    name: qm7-ibm-mq
  port:
    targetPort: 1414
  tls:
    termination: passthrough
EOF

# no need to create route (because not using channel routes) - Operator automatically generates route for hostname :: oc apply -n cp4i -f qm7chl-route.yaml

# Deploy the queue manager
cat > qm7-qmgr.yaml << EOF
apiVersion: mq.ibm.com/v1beta1
kind: QueueManager
metadata:
  name: qm7
spec:
  license:
    accept: true
    license: L-RJON-C7QG3S
    use: NonProduction
  queueManager:
    name: QM7
    ini:
      - configMap:
          name: example-07-qm7-configmap
          items:
            - qm7.ini
    mqsc:
    - configMap:
        name: example-07-qm7-configmap
        items:
        - qm7.mqsc
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
          secretName: example-07-qm7-secret
          items:
          - tls.key
          - tls.crt
    trust:
    - name: mqx1
      secret:
        secretName: example-07-mqx1-secret
        items:
          - mqx1.crt
EOF

oc apply -n $OCP_PROJECT -f qm7-qmgr.yaml

# wait 5 minutes for queue manager to be up and running
# (shouldn't take more than 2 minutes, but just in case)
for i in {1..60}
do
  phase=`oc get qmgr -n $OCP_PROJECT qm7 -o jsonpath="{.status.phase}"`
  if [ "$phase" == "Running" ] ; then break; fi
  echo "Waiting for qm7...$i"
  oc get qmgr -n $OCP_PROJECT qm7
  sleep 5
done

if [ $phase != "Running" ]
then
   echo "*** Queue Manager qm7 is not ready ***"
   exit 1
fi

echo "Queue Manager qm7 is Running"

# Create the Client Channel Definition Table (CCDT)
# Find the queue manager host name

qmhostname=`oc get route -n $OCP_PROJECT qm7-ibm-mq-qm -o jsonpath="{.spec.host}"`
echo $qmhostname

# Test:

nslookup $qmhostname

# Create ccdt.json

cat > ccdt.json << EOF
{
    "channel":
    [
        {
            "name": "QM7CHL",
            "clientConnection":
            {
                "connection":
                [
                    {
                        "host": "$qmhostname",
                        "port": 443
                    }
                ],
                "queueManager": "QM7"
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
