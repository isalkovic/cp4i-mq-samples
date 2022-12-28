# Example: Enabling queue-related metrics (like Q.depth) and configuring monitoring through CP4I Prometheus and Grafana

By default, MQ exposes certain metrics in Prometheus format, listening on port 5179. However, these metrics are related to the queue manager and do not include metrics related to queues. To monitor a metric like queue depth, we need to do some customization.

This example shows how to set up collection of these metrics from the queue manager and how to convert them (exporter) to the format required by Prometheus.

Source: These instructions are based on:
https://www.ibm.com/docs/en/ibm-mq/9.3?topic=operator-monitoring-when-using-mq
https://github.com/ibm-messaging/mq-metric-samples
https://production-gitops.dev/guides/cp4i/mq/monitoring/topic3/#enable-ci-resources
https://community.ibm.com/community/user/integration/blogs/matt-roberts1/2021/05/03/monitoring-mq-qdepth-cp4i

## Preparation

Open a terminal and login to the OpenShift cluster where you installed the CP4I MQ Operator.

Clone this repository and navigate to this directory:

```
git clone https://github.com/ibm-messaging/cp4i-mq-samples.git

```

```
cd cp4i-mq-samples/18-monitorPrometheus

```

### Clean up if not first time

Delete the files and OpenShift resources created by this example:

```
./cleanup-qm18.sh

```

# Configure and deploy the queue manager

You can copy/paste the commands shown here, or run the script [deploy-qm18-qmgr.sh](./deploy-qm18-qmgr.sh).

**Remember you must be logged in to your OpenShift cluster.**

We will not go through all the details of the deploy-qmgr script, because it is the same like in the 01-tls example, with the following configuration replacing the original:

```
DEFINE QLOCAL('Q1') REPLACE DEFPSIST(YES)
DEFINE QLOCAL('Q2') REPLACE DEFPSIST(YES)
DEFINE QLOCAL('Q3') REPLACE DEFPSIST(YES)
DEFINE CHANNEL(QM18CHL) CHLTYPE(SVRCONN) REPLACE TRPTYPE(TCP)
SET CHLAUTH(QM18CHL) TYPE(BLOCKUSER) USERLIST('nobody') ACTION(ADD)
```

Instead of one queue, we now have three, so that our metrics are more interesting. Also, we have completely removed the SSL from the channel because the channel will be accessed without SSL, through the service from within the openshift cluster.

# Deploy the extension objects, which will export the metrics to Prometheus

You can now run the script [deploy-metrics-extension.sh](./deploy-metrics-extension.sh) , which will deploy all the required resources needed to collect data from queue manager and export them to Prometheus format. These resources are:
- configmap
- secret
- deployment
- service
- servicemonitor
- serviceaccount

To simplify the process, Deployment references an image built and available on quay.io.
If you want, you can build your image using the instructions on the referenced links.

Run the script:

```
./deploy-metrics-extension.sh

```

### Put sample messages to the queue

The script above has put some messages in the queues Q1, Q2 and Q3, so that we have some data to look at in the dashboards.
If you would like, you can put some quick sample messages to the queues , to see how the dashboards are affected.
You can run the following commands, depending on the Queue where you want to put the message:

```
oc exec qm18-ibm-mq-0 -- //bin/bash -c "echo "Test1" | /opt/mqm/samp/bin/amqsput Q1 QM18"
oc exec qm18-ibm-mq-0 -- //bin/bash -c "echo "Test1" | /opt/mqm/samp/bin/amqsput Q2 QM18"
oc exec qm18-ibm-mq-0 -- //bin/bash -c "echo "Test1" | /opt/mqm/samp/bin/amqsput Q3 QM18"

```

You should see the following output, if the commands have finished successfully:

```
Sample AMQSPUT0 start
target queue is Q1
Sample AMQSPUT0 end
```

## Cleanup

This command deletes the queue manager and other objects created on OpenShift, and the files created by this example:

```
./cleanup-qm1.sh

```
