#!/usr/bin/python3

import yaml

with open("/opt/mgmt/values-ssp.yaml", 'r') as stream:
  try:
    print(yaml.safe_load(stream).get("platform").get("network").get("ipprefix"))
  except yaml.YAMLError as exc:
    print(exc)
