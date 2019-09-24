#!/usr/bin/env python

import yaml

with open("/opt/mgmt/values-ssp.yaml", 'r') as stream:
  try:
    print(yaml.safe_load(stream).get("platform").get("workers").get("ram"))
  except yaml.YAMLError as exc:
    print(exc)
