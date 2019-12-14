#!/usr/bin/env python

import os
import sys
import argparse
import yaml

try:
  import json
except ImportError:
  import simplejson as json

platform_network_ipprefix = '10.20.30'
with open("/opt/mgmt/values-ssp.yaml", 'r') as stream:
  try:
    platform_network_ipprefix = yaml.safe_load(stream).get("platform").get("network").get("ipprefix")
  except yaml.YAMLError as exc:
    platform_network_ipprefix = '10.20.30'

class Inventory(object):

  def __init__(self):
    self.inventory = {}
    self.read_cli_args()

    # Called with `--list`.
    if self.args.list:
      self.inventory = self.get_inventory()
    # Called with `--host [hostname]`.
    elif self.args.host:
      # Not implemented, since we return _meta info `--list`.
      self.inventory = self.empty_inventory()
    # If no groups or vars are present, return an empty inventory.
    else:
      self.inventory = self.empty_inventory()

    print json.dumps(self.inventory);

  # Example inventory for testing
  def get_inventory(self):
    return {
      'all': {
        'hosts': [ 'host' ],
        'children': [ 'kubernetes' ]
      },
      'kubernetes': {
        'hosts': [ 'kubemaster' ],
        'children': [ 'kubenodes' ]
      },
      'kubenodes': {
        'hosts': [ 'kubenode1', 'kubenode2' ]
      },
      '_meta': {
        'hostvars': {
          'host': {
            'ansible_host': 'localhost',
            'ansible_user': 'root'
          },
          'kubemaster': {
            'ansible_host': platform_network_ipprefix + '.110',
            'ansible_user': 'root',
            'ansible_ssh_common_args': '-o StrictHostKeyChecking=no',
            'ssp_vm': 'true'
          },
          'kubenode1': {
            'ansible_host': platform_network_ipprefix + '.111',
            'ansible_user': 'root',
            'ansible_ssh_common_args': '-o StrictHostKeyChecking=no',
            'ssp_vm': 'true'
          },
          'kubenode2': {
            'ansible_host': platform_network_ipprefix + '.112',
            'ansible_user': 'root',
            'ansible_ssh_common_args': '-o StrictHostKeyChecking=no',
            'ssp_vm': 'true'
          }
        }
      }
    }

  # Empty inventory for testing
  def empty_inventory(self):
    return {'_meta': {'hostvars': {}}}

  # Read the command line args passed to the script
  def read_cli_args(self):
    parser = argparse.ArgumentParser()
    parser.add_argument('--list', action = 'store_true')
    parser.add_argument('--host', action = 'store')
    self.args = parser.parse_args()

# Get the inventory
Inventory()
