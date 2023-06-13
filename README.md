# infoblox-illumio-sync
https://github.com/code7a/infoblox-illumio-sync

Licensed under the Apache License, Version 2.0 (the "License"); you may not
use this file except in compliance with the License. You may obtain a copy of
the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
License for the specific language governing permissions and limitations under
the License.

infoblox-illumio-sync.sh - creates illumio PCE IP lists and unmanaged workloads from infoblox networks and used ip address records

jq is required to parse results\
https://stedolan.github.io/jq/

```
usage: ./infoblox-illumio-sync.sh [options]

options:
    -n, --get-networks                  get infoblox networks
    -i, --get-ips                       get infoblox ip addresses
    -l, --create-ip-lists               create illumio pce ip lists from infoblox networks
    -u, --create-unmanaged-workloads    create illumio pce unmanaged workloads from infoblox ip addresses
    -v, --version                       returns version
    -h, --help                          returns help message

examples:
    ./infoblox-illumio-sync.sh --get-networks
    ./infoblox-illumio-sync.sh -i
    ./infoblox-illumio-sync.sh --create-ip-lists
    ./infoblox-illumio-sync.sh -l -u
    ./infoblox-illumio-sync.sh --create-unmanaged-workloads --create-ip-lists
```

#### Notes:
Only read permissions are required for infoblox.\
Read and write permissions are required for illumio PCE.\
Only clone to/execute from a user profile with restrictive permissions.