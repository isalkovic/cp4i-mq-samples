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

# Create a new ServiceAccount that will ensure the metrics pod is
# deployed using the most secure Restricted SCC
oc apply -f sa-pod-deployer.yaml

# secret needed only if qmgr requires authentication
#oc apply -f metrics-secret.yaml

oc apply -f metrics-configmap.yaml

# Update the spec.containers.image attribute in metrics-pod.yaml to match
# your container registry and image name
#vi metrics-pod.yaml

# Deploy the metrics pod using the service account
oc apply -f metrics-deployment.yaml #--as=qm1-my-service-account qm1-ibm-mq

# Create a Service object that exposes the metrics pod so that it can
# be discovered by monitoring tools that are looking for Prometheus endpoints
#
# Note that the spec.selector.app matches the metadata.labels.app property
# defined in metrics-pod.yaml
oc apply -f metrics-service.yaml

# we also need to deploy the servicemonitor, which will add a target for Prometheus to collect the metrics from.
# This command requires additional priviledges, so if it fails, you may have to involve your cluster administrator.
oc apply -f metrics-service-monitor.yaml

# Optionally, if you want to see the data being emitted by the metrics pods you can make your own call to the
# Prometheus endpoint by exec’ing into your queue manager pod and using curl to call the endpoint, for example:
oc exec qm18-ibm-mq-0 -- /bin/bash -c "curl qm18-metric-prometheus-service:9157/metrics"

oc exec qm18-ibm-mq-0 -- //bin/bash -c "echo "Test1" | /opt/mqm/samp/bin/amqsput Q1 QM18"
oc exec qm18-ibm-mq-0 -- //bin/bash -c "echo "Test1" | /opt/mqm/samp/bin/amqsput Q2 QM18"
oc exec qm18-ibm-mq-0 -- //bin/bash -c "echo "Test1" | /opt/mqm/samp/bin/amqsput Q3 QM18"
oc exec qm18-ibm-mq-0 -- //bin/bash -c "echo "Test1" | /opt/mqm/samp/bin/amqsput Q2 QM18"
oc exec qm18-ibm-mq-0 -- //bin/bash -c "echo "Test1" | /opt/mqm/samp/bin/amqsput Q3 QM18"
oc exec qm18-ibm-mq-0 -- //bin/bash -c "echo "Test1" | /opt/mqm/samp/bin/amqsput Q3 QM18"

exit 1
