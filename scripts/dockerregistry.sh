#!/bin/bash

set -e

nohup docker run -d -p 5000:5000 --name registry registry:2.7 &
