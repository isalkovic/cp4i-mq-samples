#!/bin/bash
#
#  (C) Copyright IBM Corp. 2021. All Rights Reserved.
#
# SPDX-License-Identifier: Apache-2.0
#
# Not for Production use. For demo and training only.
#

# delete queue manager
oc delete -n cp4i-mq-poc qmgr qm15
rm qm15-qmgr.yaml

# delete config map
oc delete -n cp4i-mq-poc cm example-03-qm15-configmap
rm qm15-configmap.yaml

# delete route
oc delete -n cp4i-mq-poc route example-03-qm15-route
rm qm15chl-route.yaml

# delete secrets
oc delete -n cp4i-mq-poc secret example-03-qm15-secret
oc delete -n cp4i-mq-poc secret example-03-app1-secret

# delete files
rm qm15.crt qm15.key app1key.* app1.* ccdt.json
