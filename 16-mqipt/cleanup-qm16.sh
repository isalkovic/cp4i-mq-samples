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

# delete files
rm *.crt *.key app1.* app1* *.pem *.pfx *.jks ccdt.json
