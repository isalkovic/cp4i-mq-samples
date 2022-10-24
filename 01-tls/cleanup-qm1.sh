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

# delete queue manager
oc delete -n $OCP_PROJECT qmgr qm1
rm qm1-qmgr.yaml

# delete config map
oc delete -n $OCP_PROJECT cm example-01-qm1-configmap
rm qm1-configmap.yaml

# delete route
oc delete -n $OCP_PROJECT route example-01-qm1-route
rm qm1chl-route.yaml

# delete secret
oc delete -n $OCP_PROJECT secret example-01-qm1-secret

# delete files
rm qm1.crt qm1.key app1key.* ccdt.json
