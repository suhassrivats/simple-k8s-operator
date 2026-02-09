#!/bin/bash
# etcd Explorer Script for Kubernetes
# This script simplifies accessing etcd in your Kubernetes cluster

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# etcd connection parameters
ETCD_POD="etcd-minikube"
NAMESPACE="kube-system"
ENDPOINTS="https://127.0.0.1:2379"
CACERT="/var/lib/minikube/certs/etcd/ca.crt"
CERT="/var/lib/minikube/certs/etcd/server.crt"
KEY="/var/lib/minikube/certs/etcd/server.key"

# Base etcdctl command
ETCDCTL_CMD="kubectl exec $ETCD_POD -n $NAMESPACE -- etcdctl --endpoints=$ENDPOINTS --cacert=$CACERT --cert=$CERT --key=$KEY"

# Function to print colored headers
print_header() {
    echo -e "\n${BLUE}========================================${NC}"
    echo -e "${GREEN}$1${NC}"
    echo -e "${BLUE}========================================${NC}\n"
}

# Function to execute etcdctl commands
exec_etcd() {
    $ETCDCTL_CMD "$@"
}

case "${1:-help}" in
    status)
        print_header "etcd Cluster Status"
        exec_etcd endpoint status -w table
        exec_etcd endpoint health -w table
        ;;
    
    members)
        print_header "etcd Cluster Members"
        exec_etcd member list -w table
        ;;
    
    list)
        print_header "Listing Keys with Prefix: ${2:-/registry}"
        exec_etcd get "${2:-/registry}" --prefix --keys-only | head -100
        ;;
    
    count)
        print_header "Key Count by Resource Type"
        echo -e "${YELLOW}Counting keys...${NC}\n"
        exec_etcd get /registry --prefix --keys-only | awk -F'/' '{print $2"/"$3}' | sort | uniq -c | sort -rn | head -20
        ;;
    
    get)
        if [ -z "$2" ]; then
            echo -e "${RED}Error: Please provide a key path${NC}"
            echo "Usage: $0 get <key-path>"
            exit 1
        fi
        print_header "Getting Key: $2"
        exec_etcd get "$2" --print-value-only | jq . 2>/dev/null || exec_etcd get "$2" --print-value-only | strings
        ;;
    
    watch)
        if [ -z "$2" ]; then
            echo -e "${RED}Error: Please provide a key prefix to watch${NC}"
            echo "Usage: $0 watch <key-prefix>"
            exit 1
        fi
        print_header "Watching Keys with Prefix: $2"
        echo -e "${YELLOW}Press Ctrl+C to stop watching${NC}\n"
        exec_etcd watch "$2" --prefix
        ;;
    
    pods)
        print_header "All Pods in etcd"
        exec_etcd get /registry/pods --prefix --keys-only
        ;;
    
    services)
        print_header "All Services in etcd"
        exec_etcd get /registry/services --prefix --keys-only
        ;;
    
    configmaps)
        print_header "All ConfigMaps in etcd"
        exec_etcd get /registry/configmaps --prefix --keys-only
        ;;
    
    deployments)
        print_header "All Deployments in etcd"
        exec_etcd get /registry/deployments --prefix --keys-only
        ;;
    
    crd)
        print_header "Custom Resource Definitions"
        exec_etcd get /registry/apiextensions.k8s.io/customresourcedefinitions --prefix --keys-only
        ;;
    
    custom)
        if [ -z "$2" ]; then
            print_header "All Custom Resources"
            exec_etcd get /registry/demo.mycompany.com --prefix --keys-only
        else
            print_header "Custom Resource: $2"
            exec_etcd get "/registry/demo.mycompany.com/$2" --prefix --keys-only
        fi
        ;;
    
    size)
        print_header "etcd Database Size and Usage"
        exec_etcd endpoint status -w json | jq -r '.[] | "DB Size: \(.dbSize | tonumber/1024/1024 | floor)MB, In Use: \(.dbSizeInUse | tonumber/1024/1024 | floor)MB, Leader: \(.leader)"'
        ;;
    
    compact)
        print_header "Compact etcd Database"
        REV=$(exec_etcd endpoint status -w json | jq -r '.[0].Status.header.revision')
        echo -e "${YELLOW}Current revision: $REV${NC}"
        echo -e "${YELLOW}Compacting...${NC}"
        exec_etcd compact "$REV"
        exec_etcd defrag
        echo -e "${GREEN}Done!${NC}"
        ;;
    
    search)
        if [ -z "$2" ]; then
            echo -e "${RED}Error: Please provide a search pattern${NC}"
            echo "Usage: $0 search <pattern>"
            exit 1
        fi
        print_header "Searching for Keys Matching: $2"
        exec_etcd get /registry --prefix --keys-only | grep -i "$2"
        ;;
    
    namespace)
        if [ -z "$2" ]; then
            echo -e "${RED}Error: Please provide a namespace${NC}"
            echo "Usage: $0 namespace <namespace-name>"
            exit 1
        fi
        print_header "All Resources in Namespace: $2"
        exec_etcd get /registry --prefix --keys-only | grep "/$2/"
        ;;
    
    revision)
        print_header "etcd Revision Information"
        exec_etcd endpoint status -w json | jq -r '.[] | "Current Revision: \(.Status.header.revision), Raft Term: \(.Status.raftTerm), Raft Index: \(.Status.raftIndex)"'
        ;;
    
    help|*)
        echo -e "${GREEN}etcd Explorer - Kubernetes etcd Helper Script${NC}\n"
        echo "Usage: $0 <command> [args]"
        echo ""
        echo -e "${YELLOW}Cluster Information:${NC}"
        echo "  status              - Show etcd cluster status and health"
        echo "  members             - List etcd cluster members"
        echo "  size                - Show database size and usage"
        echo "  revision            - Show current revision and Raft info"
        echo ""
        echo -e "${YELLOW}Data Exploration:${NC}"
        echo "  list [prefix]       - List keys (default: /registry)"
        echo "  count               - Count keys by resource type"
        echo "  get <key>           - Get value for a specific key"
        echo "  search <pattern>    - Search for keys matching pattern"
        echo "  namespace <ns>      - Show all resources in a namespace"
        echo ""
        echo -e "${YELLOW}Resource Queries:${NC}"
        echo "  pods                - List all pods"
        echo "  services            - List all services"
        echo "  configmaps          - List all configmaps"
        echo "  deployments         - List all deployments"
        echo "  crd                 - List custom resource definitions"
        echo "  custom [type]       - List custom resources"
        echo ""
        echo -e "${YELLOW}Monitoring:${NC}"
        echo "  watch <prefix>      - Watch for changes on keys"
        echo ""
        echo -e "${YELLOW}Maintenance:${NC}"
        echo "  compact             - Compact and defragment etcd database"
        echo ""
        echo -e "${YELLOW}Examples:${NC}"
        echo "  $0 status"
        echo "  $0 get /registry/pods/default/my-pod"
        echo "  $0 watch /registry/pods/default"
        echo "  $0 search nginx"
        echo "  $0 namespace default"
        echo "  $0 custom configmapapps"
        ;;
esac
