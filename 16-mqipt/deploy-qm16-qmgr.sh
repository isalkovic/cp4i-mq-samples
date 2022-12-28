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

# Create a private key and a self-signed certificate for the MQIPT - store it in .pfx keystore
keytool -genkeypair -keystore mqiptServer.pfx -storetype PKCS12 -storepass password -alias mqiptcert -keyalg RSA -keysize 2048 -validity 99999 -dname "CN=DESKTOP-GIQAQ2O"

# From the generated keystore, gnerate and export the public certificate (to be later imported to client truststores)
keytool -exportcert -keystore mqiptServer.pfx -storepass password -alias mqiptcert -rfc -file mqipt-public-cert.pem

# Create JKS trust store for MQ Explorer and import into it the MQIPT public key
keytool -importcert -file mqipt-public-cert.pem -alias mqiptcert -keystore client-truststore.jks -storetype jks -storepass password -noprompt

# List the trust store certificate
keytool -list -keystore client-truststore.jks -storepass password

# Create the client key database (for MQ clients which require .kdb type):
runmqakm -keydb -create -db app1key.kdb -pw password -type cms -stash

# Add the MQIPT public key to the client key database:
runmqakm -cert -add -db app1key.kdb -label mqiptcert -file mqipt-public-cert.pem -format ascii -stashed

# Check. List the database certificates:
runmqakm -cert -list -db app1key.kdb -stashed

# Copy the public certificate from QM1 example and add it to the MQIPT's truststores
cp ../01-tls/qm1.crt ../01-tls/APIS_root_certificate.crt .
keytool -importcert -storetype PKCS12 -keystore mqiptClient.pfx -storepass password -alias qm1cert -file qm1.crt -noprompt
keytool -importcert -storetype PKCS12 -keystore mqiptClient.pfx -storepass password -alias apisrootcert -file APIS_root_certificate.crt -noprompt


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

if [ $phase != Running ]
   then echo "***Queue Manager qm1 is not ready ***";
   exit 1;
fi

echo "*** Queue Manager qm1 is ready ***"

# Create the Client Channel Definition Table (CCDT)
# Find the queue manager host name
