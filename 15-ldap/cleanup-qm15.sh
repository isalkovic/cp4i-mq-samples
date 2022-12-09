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

# delete queue manager
oc delete -n $OCP_PROJECT qmgr qm15
rm qm15-qmgr.yaml

# delete config map
oc delete -n $OCP_PROJECT cm example-15-qm15-configmap
rm qm15-configmap.yaml

# delete route
# oc delete -n $OCP_PROJECT route example-03-qm15-route
rm qm15chl-route.yaml

# delete secrets
oc delete -n $OCP_PROJECT secret example-15-qm15-secret

# delete files
rm qm15.crt qm15.key mqx1* app1* ccdt.json
