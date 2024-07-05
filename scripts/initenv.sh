#!/bin/bash

set -e

echo "$IP_BASE.$IP_REGISTRY registry registry.11" >> /etc/hosts
echo "$IP_BASE.$IP_STORAGE storage storage.$HOST" >> /etc/hosts
