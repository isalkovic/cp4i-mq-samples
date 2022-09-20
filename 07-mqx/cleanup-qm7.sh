#!/bin/bash
#
#  (C) Copyright IBM Corp. 2021. All Rights Reserved.
#
# SPDX-License-Identifier: Apache-2.0
#
# Not for Production use. For demo and training only.
#

# delete queue manager
oc delete -n $OCP_PROJECT qmgr qm7
rm qm7-qmgr.yaml

# delete config map
oc delete -n $OCP_PROJECT cm example-07-qm7-configmap
rm qm7-configmap.yaml

# delete route
# oc delete -n $OCP_PROJECT route example-07-qm7-route
rm qm7chl-route.yaml

# delete secrets
oc delete -n $OCP_PROJECT secret example-07-qm7-secret
oc delete -n $OCP_PROJECT secret example-07-mqx1-secret

# delete files
rm qm7.crt qm7.key mqx1-* mqx1.* ccdt.json
