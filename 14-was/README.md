# Example: Conencting to MQ on Openshift from Websphere Liberty application


## Preparation

### Download MQ Resource adapter
https://www.ibm.com/support/pages/obtaining-ibm-mq-resource-adapter-websphere-application-server-liberty-profile

The WebSphere MQ Resource Adapter can be downloaded from Fix Central. To locate the latest version that is available for download, enter the phrase "Resource Adapter" in the Text Search box. The name of the file to be downloaded will be in the format of <V.R.M.F>-WS-MQ-Java-InstallRA.jar. From version IBM MQ v9 this format is <V.R.M.F>-IBM-MQ-Java-InstallRA.jar

To start the installation, issue the following command from the directory to which you downloaded the file. Note that this command requires a Java™ Runtime Environment to be installed on your machine and added to the system path:
java -jar <V.R.M.F>-WS-MQ-Java-InstallRA.jar

Within the selected directory a new directory 'wmq' will be created. Inside the 'wmq' directory, the following files are installed:
wmq.jmsra.ivt.ear
wmq.jmsra.rar
The wmq.jmsra.ivt.ear is the installation verification test program. The wmq.jmsra.rar is the WebSphere MQ Resource Adapter RAR file.

Documentation on adapter:
https://www.ibm.com/docs/en/ibm-mq/9.3?topic=adapter-liberty-mq-resource
- The IBM MQ 9.0 resource adapter can be used with wmqJmsClient-2.0 feature only.

Add the following lines to Liberty's server.xml to reference the location of resource adapter:
```
<variable name="wmqJmsClient.rar.location" value="yourpathmqresourceadapter\wmq.jmsra.rar"/>
<resourceAdapter id="mqJms" location="${server.config.dir}/wmq.jmsra.rar">
  <classloader apiTypeVisibility="spec, ibm-api, api, third-party"/>        
</resourceAdapter>
```

Add the following lines to Liberty's server.xml to enable required Liberty features:
```
<featureManager>
      <feature>wmqJmsClient-2.0</feature>
      <feature>servlet-3.1</feature>     
    	<feature>jndi-1.0</feature>    
    	<feature>jca-1.7</feature>      
    	<feature>jms-2.0</feature>   
</featureManager>
```

Add the following lines to Liberty's server.xml to configure JMS connection parameters for the use by the MQ IVT application:
```
<!-- IVT Connection factory -->
<jmsQueueConnectionFactory connectionManagerRef="ConMgrIVT" jndiName="IVTCF">
   <properties.wmqJms channel="QM7CHL" hostname="qm7-ibm-mq-qm-cp4i-mq-poc.apps.poc.openshift.local" port="443" transportType="CLIENT"/>
</jmsQueueConnectionFactory>
<connectionManager id="ConMgrIVT" maxPoolSize="10"/>

<!-- IVT Queues -->
<jmsQueue id="IVTQueue" jndiName="IVTQueue">
   <properties.wmqJms baseQueueName="TEST"/>
</jmsQueue>

<!-- IVT Activation Spec -->
<jmsActivationSpec id="wmq.jmsra.ivt/WMQ_IVT_MDB/WMQ_IVT_MDB">    
   <properties.wmqJms destinationRef="IVTQueue"
transportType="CLIENT"
queueManager="QM7"
hostName="qm7-ibm-mq-qm-cp4i-mq-poc.apps.poc.openshift.local"
port="443"
maxPoolDepth="1"/>
</jmsActivationSpec>
```

create new server on liberty

install required features specified in server.xml:
/bin/installUtility install mq_test
```
Checking for missing features required by the server ...
Establishing a connection to the configured repositories ...
This process might take several minutes to complete.

Successfully connected to all configured repositories.

Preparing assets for installation. This process might take several minutes to complete.
The server requires the following additional features: servlet-3.1 wmqJmsClient-2.0 jndi-1.0 jca-1.7 jms-2.0.  Installing features from the repository ...

Additional Liberty features must be installed for this server.

To install the additional features, review and accept the feature license agreement:
Step 1 of 12: Downloading servlet-3.1 ...
Step 2 of 12: Installing servlet-3.1 ...
Step 3 of 12: Downloading wmqJmsClient-2.0 ...
Step 4 of 12: Installing wmqJmsClient-2.0 ...
Step 5 of 12: Downloading jndi-1.0 ...
Step 6 of 12: Installing jndi-1.0 ...
Step 7 of 12: Downloading jca-1.7 ...
Step 8 of 12: Installing jca-1.7 ...
Step 9 of 12: Downloading jms-2.0 ...
Step 10 of 12: Installing jms-2.0 ...
Step 11 of 12: Validating installed fixes ...
Step 12 of 12: Cleaning up temporary files ...


All assets were successfully installed.

Start product validation...
Product validation completed successfully.
```

Copy the IVT ear ( wmq.jmsra.ivt.ear ) to Liberty dropins folder.

start liberty server:
 ./bin/server start mq_test

# Websphere Application Server (traditional) configuration

- wmq.jms.rar is already a part of WAS installation:
https://www.ibm.com/docs/en/ibm-mq/9.2?topic=together-using-websphere-application-server-mq

- following these instructions:
https://www.ibm.com/docs/en/was/9.0.5?topic=SSEQTP_9.0.5/com.ibm.websphere.nd.multiplatform.doc/ae/umj_pjmsw.html


Open a terminal and login to the OpenShift cluster where you installed the CP4I MQ Operator.

If not already done, clone this repository and navigate to this directory:

```
git clone https://github.com/isalkovic/cp4i-mq-samples.git

```

```
cd cp4i-mq-samples/07-mqx

```
### Set Openshift project name
In the terminal, run the following command (or appropriate depending on your OS/environment):
```
export OCP_PROJECT=cp4i-mq-poc
```

Remember to change the name of the project to the actual Project name on Openshift, which you will be using.
You can check that the value is set properly by running the following command:
```
echo $OCP_PROJECT
```

### Clean up if not first time

Delete the files and OpenShift resources created by this example:

```
./cleanup-qm7.sh

```

# Configure and deploy the queue manager

You can copy/paste the commands shown here, or run the script [deploy-qm7-qmgr.sh](./deploy-qm7-qmgr.sh).

**Remember you must be logged in to your OpenShift cluster.**

## Setup TLS for the queue manager

### Create a private key and a self-signed certificate for the queue manager

```
openssl req -newkey rsa:2048 -nodes -keyout qm7.key -subj "//CN=qm7" -x509 -days 3650 -out qm7.crt

```

## Setup TLS for MQ Explorer

MQ Explorer is a Java application. Java applications use a different type of key store, called `JKS`. In JKS, there are two stores:

* Trust store: this will contain the queue manager's signer (CA) certificate. In this case, as the queue manager's certificate is self-signed, the trust store will contain the queue manager's certificate itself.

* Key store: this will contain the client's (that is, MQ Explorer's) certificate and private key.

### Import the Queue Manager's certificate into a JKS trust store

This will create a file called `mqx1-truststore.jks`.

```
keytool -importcert -file qm7.crt -alias qm7cert -keystore mqx1-truststore.jks -storetype jks -storepass password -noprompt

```

### IVO:: import also APIS certificates to client's JKS trust store
Before running the following commands, make sure you have acquired the root certificate and that it is available with the name referenced in the command:
```
keytool -keystore mqx1-truststore.jks -storetype jks -import -file APIS_root_certificate.crt -alias apisrootcert -storepass password -noprompt
```

List the trust store certificate:

```
keytool -list -keystore mqx1-truststore.jks -storepass password

```

Output should be similar to this (truncated for readability; ignore the warning about proprietary format):

```
qm7cert, 7 Dec 2021, trustedCertEntry,
Certificate fingerprint (SHA-256): 96:62:71:B8:46:AE:48:A0:02:E0:74:BD...
apisrootcert, 20. ruj 2022., trustedCertEntry,
Certificate fingerprint (SHA-256): F1:E7:73:46:E4:FC:E0:34:83:E3:94:9D:...
qm7cert, 20. ruj 2022., trustedCertEntry,
Certificate fingerprint (SHA-256): E8:A4:E1:08:ED:00:A9:57:E9:59:F9:75:...


```

### Create a private key and a self-signed certificate for MQ Explorer

```
openssl req -newkey rsa:2048 -nodes -keyout mqx1.key -subj "//CN=mqx1" -x509 -days 3650 -out mqx1.crt

```

#### Add MQ Explorer's certificate and key to a JKS key store

First, put the key (`mqx1.key`) and certificate (`mqx1.crt`) into a PKCS12 file. PKCS12 is a format suitable for importing into the JKS key store (`mqx1-keystore.jks`):

```
openssl pkcs12 -export -out mqx1.p12 -inkey mqx1.key -in mqx1.crt -name mqx1 -password pass:password

```

Next, import the PKCS12 file into a JKS store (this creates the key store; ignore the warning about proprietary format):

```
keytool -importkeystore -deststorepass password -destkeypass password -destkeystore mqx1-keystore.jks -deststoretype jks -srckeystore mqx1.p12 -srcstoretype PKCS12 -srcstorepass password -alias mqx1

```

List the key store certificate:

```
keytool -list -keystore mqx1-keystore.jks -alias mqx1 -storepass password

```

Output should be similar to this (truncated for readability; ignore the warning about proprietary format):

```
mqx1, 7 Dec 2021, PrivateKeyEntry,
Certificate fingerprint (SHA-256): 95:17:91:9C:09:A1:64:5D:23:AF:66:BA...

```

### Create TLS Secret for the Queue Manager

```
oc create secret tls example-07-qm7-secret -n $OCP_PROJECT --key="qm7.key" --cert="qm7.crt"

```

### Create TLS Secret with the client's certificate

```
oc create secret generic example-07-mqx1-secret -n $OCP_PROJECT --from-file=mqx1.crt=mqx1.crt

```

## Setup and deploy the queue manager

### Create a config map containing MQSC commands and qm.ini

#### Create the config map yaml file

The specific here is the we need to set "OutboundSNI=HOSTNAME" in the .ini file.

```
cat > qm7-configmap.yaml << EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: example-07-qm7-configmap
data:
  qm7.mqsc: |
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
    Service:
      Name=AuthorizationService
      EntryPoints=14
      SecurityPolicy=UserExternal
    SSL:
      OutboundSNI=HOSTNAME
EOF
#
cat qm7-configmap.yaml

```

#### Note:

* SET AUTHREC commands

```
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
```

These commands give user `mqx1` full administrative rights. They are based on the `setmqaut` commands documented in [Granting full administrative access to all resources on a queue manager](https://www.ibm.com/docs/en/ibm-mq/9.3?topic=grar-granting-full-administrative-access-all-resources-queue-manager).

#### Create the config map

```
oc apply -n $OCP_PROJECT -f qm7-configmap.yaml

```


### Deploy the queue manager

#### Create the queue manager's yaml file

```
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
#
cat qm7-qmgr.yaml

```
#### Create the queue manager

```
oc apply -n $OCP_PROJECT -f qm7-qmgr.yaml

```

### Confirm that the queue manager is running

```
oc get qmgr -n $OCP_PROJECT qm7

```

## Create the Channel Table (CCDT) for MQ Explorer

### Find the queue manager host name

```
qmhostname=`oc get route -n $OCP_PROJECT qm7-ibm-mq-qm -o jsonpath="{.spec.host}"`
echo $qmhostname

```

Test (optional):
```
nslookup $qmhostname

```

### Create ccdt.json

```
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
#
cat ccdt.json

```




# Connect MQ Explorer

## Define mqclient.ini file

As the last step before starting and configuring MQ Explorer, we need to tell MQ Explorer to connect to the MQ server using HOSTNAME, instead of CHANNEL (default is CHANNEL).
To do so, we need to create a mqclient.ini file and put it on one of the location where it will be found. It must contain at least the following content:

```
SSL:
   AllowTLSV13=TRUE
   OutboundSNI=HOSTNAME
```
For location of the mqclient.ini file on Windows, I have used "C:\ProgramData\IBM\MQ".
Other possible locations are specified in MQ documentation:
https://www.ibm.com/docs/en/ibm-mq/9.3?topic=file-location-client-configuration

An example mqclient.ini file is provided along with this documentation.

## Add remote QMGR to MQ Explorer

1. Start MQ Explorer.

2. Right-click on `Queue Managers` (top left) and select `Add Remote Queue Manager...`

![add remote QMGR](./images/mqexplorer01.png)

3. Enter the queue manager name (`QM7`, case sensitive) and select the `Connect using a client channel definition table` radio button. Click `Next`.

![QMGR name](./images/mqexplorer02.png)

4. On the next pane (`Specify new connection details`), click `Browse...` and select the file `ccdt.json` just created. Click `Next`.

![add CCDT](./images/mqexplorer03.png)

5. On `Specify SSL certificate key repository details, tick `Enable SSL key repositories`.

5.1. On `Trusted Certificate Store` click on `Browse...` and select the file `mqx1-truststore.jks`.

![SSL repos](./images/mqexplorer04.png)

5.2. Select `Enter password...` and enter the trust store password (in our case, `password`).

![SSL repos password](./images/mqexplorer05.png)

5.3. On `Personal Certificate Store` click on `Browse...` and select the file `mqx1-keystore.jks`.

5.4. Select `Enter password...` and enter the key store password (in our case, `password`).

Click `Finish`.

![Finish](./images/mqexplorer06.png)

You should now have a connection to your QMGR deployed on Openshift.

## Cleanup

This deletes the queue manager and other objects created on OpenShift, and the files created by this example:

```
./cleanup-qm7.sh

```

This is the end of the MQ Explorer example.
