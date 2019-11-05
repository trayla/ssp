#!/bin/bash

if [ "$1" == "storage" ]; then
  if [ "$2" == "list" ]; then
    kubectl get pv -o custom-columns=PV:".metadata.uid",CLAIM_NS:".spec.claimRef.namespace",CLAIM_NAME:".spec.claimRef.name",HEKETI_ID:".metadata.annotations.gluster\.kubernetes\.io/heketi-volume-id"
  fi
fi

