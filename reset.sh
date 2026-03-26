#!/bin/bash
###############################################################################
# reset.sh
#
# Purpose:
#   Selective or full cleanup and reset of local DevOps tooling.
#   User chooses which services/components to remove.
#
# WARNING:
#   This script is DESTRUCTIVE. Use only when your environment is
#   unrecoverable or you need a clean slate.
###############################################################################

set -uo pipefail
IFS=$'\n\t'

# INLINE COLORS (standalone script — does not source lib/colors.sh)
if [[ -t 1 ]]; then
    RESET=$'\e[0m';        BOLD=$'\e[1m';         DIM=$'\e[2m'
    RED=$'\e[38;5;196m';   GREEN=$'\e[38;5;82m';  YELLOW=$'\e[38;5;220m'
    CYAN=$'\e[38;5;51m';   BRIGHT_WHITE=$'\e[38;5;231m'
    BRIGHT_CYAN=$'\e[38;5;87m'; BRIGHT_GREEN=$'\e[38;5;46m'
    ORANGE=$'\e[38;5;208m'
    BG_RED=$'\e[48;5;52m'; BG_GREEN=$'\e[48;5;22m'; BG_YELLOW=$'\e[48;5;58m'
else
    RESET=''; BOLD=''; DIM=''; RED=''; GREEN=''; YELLOW=''; CYAN=''
    BRIGHT_WHITE=''; BRIGHT_CYAN=''; BRIGHT_GREEN=''; ORANGE=''
    BG_RED=''; BG_GREEN=''; BG_YELLOW=''
fi

# PRINT PRIMITIVES
_SEP_HEAVY="  ============================================================================"
_SEP_LIGHT="  ----------------------------------------------------------------------------"

print_header() {
    local title="$1"
    echo ""
    echo -e "${BOLD}${BRIGHT_CYAN}${_SEP_HEAVY}${RESET}"
    echo -e "${BOLD}${BRIGHT_CYAN}|${RESET}  ${BOLD}${BRIGHT_WHITE}${title}${RESET}"
    echo -e "${BOLD}${BRIGHT_CYAN}${_SEP_HEAVY}${RESET}"
    echo ""
}

print_section() {
    echo ""
    echo -e "  ${BOLD}${YELLOW}>>  $1${RESET}"
    echo -e "${DIM}${YELLOW}${_SEP_LIGHT}${RESET}"
}

print_ok()   { echo -e "  ${BOLD}${BG_GREEN}${BRIGHT_WHITE} OK ${RESET}  ${BRIGHT_GREEN}$1${RESET}"; }
print_warn() { echo -e "  ${BOLD}${BG_YELLOW}${BOLD} !! ${RESET}  ${YELLOW}$1${RESET}"; }
print_err()  { echo -e "  ${BOLD}${BG_RED}${BRIGHT_WHITE} XX ${RESET}  ${RED}$1${RESET}"; }
print_step() { echo -e "  ${BOLD}${CYAN}  ->  ${RESET}${DIM}$1${RESET}"; }
print_skip() { echo -e "  ${DIM}  --  $1 -- skipped${RESET}"; }

print_danger_box() {
    local line1="$1"
    local line2="${2:-}"
    echo ""
    echo -e "${BOLD}${RED}+============================================================================+${RESET}"
    echo -e "${BOLD}${RED}|${RESET}  ${BOLD}${RED}!! DANGER !!${RESET}  ${BOLD}${BRIGHT_WHITE}DESTRUCTIVE ACTION${RESET}"
    echo -e "${BOLD}${RED}+============================================================================+${RESET}"
    echo -e "${BOLD}${RED}|${RESET}  ${RED}${line1}${RESET}"
    [[ -n "$line2" ]] && echo -e "${BOLD}${RED}|${RESET}  ${RED}${line2}${RESET}"
    echo -e "${BOLD}${RED}+============================================================================+${RESET}"
    echo ""
}

# SAFETY GUARDS
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    echo "ERROR: Do not source this script — execute it directly."
    return 1 2>/dev/null || exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

# SELECTION STATE — all off by default
SEL_APP=false
SEL_MONITORING=false
SEL_LOKI=false
SEL_TRIVY=false
SEL_ARGOCD=false
SEL_GITLAB_RUNNER=false
SEL_KUBERNETES=false
SEL_MINIKUBE=false
SEL_DOCKER_CONTAINERS=false
SEL_DOCKER_NETWORK_STATE=false
SEL_PORTS=false
SEL_REBOOT=false

toggle() {
    local var="$1"
    if [[ "${!var}" == "true" ]]; then
        printf -v "$var" "false"
    else
        printf -v "$var" "true"
    fi
}

# INTERACTIVE MENU
show_menu() {
    clear

    echo ""
    echo -e "${BOLD}${BRIGHT_CYAN}+============================================================================+${RESET}"
    echo -e "${BOLD}${BRIGHT_CYAN}|${RESET}  ${BOLD}${BRIGHT_WHITE}DevOps Environment  --  Selective Cleanup & Reset${RESET}"
    echo -e "${BOLD}${BRIGHT_CYAN}+============================================================================+${RESET}"
    echo ""
    echo -e "  ${BOLD}${BG_YELLOW}${BOLD} !! ${RESET}  ${YELLOW}${BOLD}DESTRUCTIVE${RESET}${YELLOW} — selected items will be permanently removed.${RESET}"
    echo -e "  ${DIM}Toggle items by number. Press ${BOLD}Enter${RESET}${DIM} when ready to proceed.${RESET}"
    echo ""
    echo -e "${DIM}${_SEP_LIGHT}${RESET}"
    echo ""

    local items=(
        "SEL_APP"                  "Application           devops-app namespace & workloads"
        "SEL_MONITORING"           "Monitoring            Prometheus + Grafana (monitoring ns)"
        "SEL_LOKI"                 "Loki                  Log aggregation (loki namespace)"
        "SEL_TRIVY"                "Trivy                 Security scanner & exporter (trivy-system ns)"
        "SEL_ARGOCD"               "ArgoCD                argocd namespace + CRDs"
        "SEL_GITLAB_RUNNER"        "GitLab Runner         Unregister + stop"
        "SEL_KUBERNETES"           "Kubernetes            Delete all workloads (keeps cluster)"
        "SEL_MINIKUBE"             "Minikube              STOP & DELETE cluster + ~/.minikube"
        "SEL_DOCKER_CONTAINERS"    "Docker Containers     Remove ALL containers & networks"
        "SEL_DOCKER_NETWORK_STATE" "Docker Network State  Wipe internal state (needs root + restart)"
        "SEL_PORTS"                "Kill Ports            3000  3001  30001-30003"
        "SEL_REBOOT"               "Reboot                Restart system after cleanup"
    )

    local i=1
    for (( idx=0; idx<${#items[@]}; idx+=2 )); do
        local var="${items[$idx]}"
        local label="${items[$((idx+1))]}"
        local state="${!var}"
        local mark pad
        if [[ "$state" == "true" ]]; then
            mark="${BOLD}${BRIGHT_GREEN}[+]${RESET}"
        else
            mark="${DIM}[ ]${RESET}"
        fi
        printf "    %s  ${BOLD}${CYAN}%2d)${RESET}  %s\n" "$mark" "$i" "$label"
        ((i++))
    done

    echo ""
    echo -e "${DIM}${_SEP_LIGHT}${RESET}"
    echo ""
    echo -e "    ${BOLD}${ORANGE} a)${RESET}  Select ALL"
    echo -e "    ${BOLD}${ORANGE} n)${RESET}  Select NONE"
    echo -e "    ${BOLD}${RED}    q)${RESET}  Quit — exit without changes"
    echo ""
}

select_services() {
    local items=(
        "SEL_APP"
        "SEL_MONITORING"
        "SEL_LOKI"
        "SEL_TRIVY"
        "SEL_ARGOCD"
        "SEL_GITLAB_RUNNER"
        "SEL_KUBERNETES"
        "SEL_MINIKUBE"
        "SEL_DOCKER_CONTAINERS"
        "SEL_DOCKER_NETWORK_STATE"
        "SEL_PORTS"
        "SEL_REBOOT"
    )

    while true; do
        show_menu
        read -rp "$(echo -e "  ${BOLD}${CYAN}Choice${RESET}${DIM} (number / a / n / Enter / q):${RESET} ")" choice

        case "$choice" in
            q|Q)
                echo ""
                print_warn "Aborted by user — nothing was changed."
                exit 0
                ;;
            a|A)
                for var in "${items[@]}"; do printf -v "$var" "true"; done
                ;;
            n|N)
                for var in "${items[@]}"; do printf -v "$var" "false"; done
                ;;
            "")
                local count=0
                for var in "${items[@]}"; do [[ "${!var}" == "true" ]] && ((count++)) || true; done
                if [[ "$count" -eq 0 ]]; then
                    echo ""
                    print_warn "Nothing selected. Pick at least one item, or press q to quit."
                    sleep 2
                    continue
                fi
                break
                ;;
            *)
                local num="$choice"
                if [[ "$num" =~ ^[0-9]+$ ]] && (( num >= 1 && num <= ${#items[@]} )); then
                    toggle "${items[$((num-1))]}"
                else
                    print_err "Invalid input: '$choice'"
                    sleep 1
                fi
                ;;
        esac
    done
}

# SUMMARY & FINAL CONFIRMATION
confirm_selection() {
    clear

    echo ""
    echo -e "${BOLD}${RED}+============================================================================+${RESET}"
    echo -e "${BOLD}${RED}|${RESET}  ${BOLD}${BRIGHT_WHITE}Cleanup Plan  --  Review Before Proceeding${RESET}"
    echo -e "${BOLD}${RED}+============================================================================+${RESET}"
    echo -e "${BOLD}${RED}|${RESET}                                                                            ${BOLD}${RED}|${RESET}"
    echo -e "${BOLD}${RED}|${RESET}  ${BOLD}${BRIGHT_WHITE}The following will be permanently destroyed:${RESET}"
    echo -e "${BOLD}${RED}|${RESET}                                                                            ${BOLD}${RED}|${RESET}"

    [[ "$SEL_APP"                  == true ]] && echo -e "${BOLD}${RED}|${RESET}    ${BOLD}${RED}(X)${RESET}  Application          devops-app namespace"
    [[ "$SEL_MONITORING"           == true ]] && echo -e "${BOLD}${RED}|${RESET}    ${BOLD}${RED}(X)${RESET}  Prometheus + Grafana  monitoring namespace"
    [[ "$SEL_LOKI"                 == true ]] && echo -e "${BOLD}${RED}|${RESET}    ${BOLD}${RED}(X)${RESET}  Loki                  loki namespace"
    [[ "$SEL_TRIVY"                == true ]] && echo -e "${BOLD}${RED}|${RESET}    ${BOLD}${RED}(X)${RESET}  Trivy                 trivy-system namespace"
    [[ "$SEL_ARGOCD"               == true ]] && echo -e "${BOLD}${RED}|${RESET}    ${BOLD}${RED}(X)${RESET}  ArgoCD                argocd namespace + CRDs"
    [[ "$SEL_GITLAB_RUNNER"        == true ]] && echo -e "${BOLD}${RED}|${RESET}    ${BOLD}${RED}(X)${RESET}  GitLab Runner         unregister + stop"
    [[ "$SEL_KUBERNETES"           == true ]] && echo -e "${BOLD}${RED}|${RESET}    ${BOLD}${RED}(X)${RESET}  Kubernetes workloads  cluster preserved"
    [[ "$SEL_MINIKUBE"             == true ]] && echo -e "${BOLD}${RED}|${RESET}    ${BOLD}${RED}(X)${RESET}  Minikube              FULL DESTROY + ~/.minikube"
    [[ "$SEL_DOCKER_CONTAINERS"    == true ]] && echo -e "${BOLD}${RED}|${RESET}    ${BOLD}${RED}(X)${RESET}  Docker containers     ALL containers & networks"
    [[ "$SEL_DOCKER_NETWORK_STATE" == true ]] && echo -e "${BOLD}${RED}|${RESET}    ${BOLD}${RED}(X)${RESET}  Docker network state  service restart required"
    [[ "$SEL_PORTS"                == true ]] && echo -e "${BOLD}${RED}|${RESET}    ${BOLD}${RED}(X)${RESET}  Kill ports            3000  3001  30001-30003"
    [[ "$SEL_REBOOT"               == true ]] && echo -e "${BOLD}${RED}|${RESET}    ${BOLD}${YELLOW}(~)${RESET}  System reboot         after cleanup"

    echo -e "${BOLD}${RED}|${RESET}                                                                            ${BOLD}${RED}|${RESET}"
    echo -e "${BOLD}${RED}+============================================================================+${RESET}"
    echo ""
    echo -e "  ${BOLD}${RED}This cannot be undone.${RESET}"
    echo ""

    read -rp "$(echo -e "  ${BOLD}${RED}Type 'yes' to confirm and start cleanup:${RESET} ")" FINAL
    if [[ "$FINAL" != "yes" ]]; then
        echo ""
        print_warn "Going back to menu..."
        sleep 1
        return 1
    fi
    return 0
}

# CLEANUP FUNCTIONS

run_kubectl() {
    kubectl "$@" 2>/dev/null || true
}

clean_app() {
    print_section "Application  (devops-app)"
    print_step "Deleting devops-app namespace and all resources..."
    run_kubectl delete namespace devops-app --ignore-not-found=true
    run_kubectl delete configmap prometheus-config -n devops-app
    print_ok "Application namespace removed"
}

clean_monitoring() {
    print_section "Prometheus + Grafana"
    print_step "Deleting monitoring namespace..."
    run_kubectl delete namespace monitoring --ignore-not-found=true
    print_step "Removing any lingering monitoring PVCs across namespaces..."
    run_kubectl delete pvc prometheus-pvc grafana-pvc -n monitoring
    print_ok "Prometheus + Grafana removed"
}

clean_loki() {
    print_section "Loki"
    print_step "Deleting loki namespace, StatefulSets, PVCs, and Promtail pods..."
    run_kubectl delete namespace loki --ignore-not-found=true
    run_kubectl delete statefulset loki -n loki
    run_kubectl delete pvc -n loki --all
    run_kubectl delete pod -l app=promtail -n loki
    print_ok "Loki removed"
}

clean_trivy() {
    print_section "Trivy"
    print_step "Deleting trivy-system namespace..."
    run_kubectl delete namespace trivy-system --ignore-not-found=true
    run_kubectl delete namespace trivy --ignore-not-found=true
    run_kubectl delete deployment trivy -n devops-app
    run_kubectl delete svc trivy -n devops-app
    run_kubectl delete pvc trivy-reports-pvc -n trivy-system
    print_ok "Trivy removed"
}

clean_argocd() {
    print_section "ArgoCD"
    print_step "Removing ArgoCD Applications..."
    run_kubectl delete applications.argoproj.io --all -n argocd

    print_step "Removing ArgoCD AppProjects..."
    run_kubectl delete appprojects.argoproj.io --all -n argocd

    print_step "Deleting argocd namespace..."
    run_kubectl delete namespace argocd --ignore-not-found=true

    print_step "Removing ArgoCD CRDs..."
    run_kubectl delete crd \
        applications.argoproj.io \
        applicationsets.argoproj.io \
        appprojects.argoproj.io \
        2>/dev/null || true

    print_step "Removing ArgoCD ClusterRoles and ClusterRoleBindings..."
    run_kubectl delete clusterrole          -l app.kubernetes.io/part-of=argocd
    run_kubectl delete clusterrolebinding   -l app.kubernetes.io/part-of=argocd

    print_ok "ArgoCD fully removed"
}

clean_gitlab_runner() {
    print_section "GitLab Runner"
    if command -v gitlab-runner >/dev/null 2>&1; then
        print_step "Unregistering all runners..."
        sudo gitlab-runner unregister --all-runners 2>/dev/null || true
        print_step "Stopping GitLab Runner service..."
        sudo gitlab-runner stop 2>/dev/null || true
        print_ok "GitLab Runner unregistered and stopped"
    else
        print_skip "gitlab-runner binary not found"
    fi
}

clean_kubernetes_workloads() {
    print_section "Kubernetes Workloads  (cluster preserved)"
    print_step "Deleting all deployments across all namespaces..."
    run_kubectl delete deployments --all --all-namespaces
    print_step "Deleting all services (except kubernetes system service)..."
    run_kubectl delete svc --all -n default
    print_step "Clearing kube cache..."
    rm -rf ~/.kube/cache
    print_ok "Kubernetes workloads removed (cluster is still running)"
}

clean_minikube() {
    print_section "Minikube"
    if command -v minikube >/dev/null 2>&1; then
        print_step "Stopping Minikube..."
        minikube stop 2>/dev/null || true
        print_step "Deleting Minikube cluster..."
        minikube delete --all 2>/dev/null || true
        print_step "Removing ~/.minikube state directory..."
        rm -rf ~/.minikube
        print_step "Removing ~/.kube/cache..."
        rm -rf ~/.kube/cache
        print_ok "Minikube fully destroyed"
    else
        print_skip "minikube not found"
    fi
}

clean_docker_containers() {
    print_section "Docker Containers & Networks"
    print_step "Bringing down docker compose stack..."
    sudo docker compose down --remove-orphans 2>/dev/null || true
    print_step "Removing all Docker containers..."
    # SC2046 — word splitting is intentional here (list of container IDs)
    # shellcheck disable=SC2046
    sudo docker rm -f $(sudo docker ps -aq 2>/dev/null) 2>/dev/null || true
    print_step "Pruning Docker networks..."
    sudo docker network rm devops_default 2>/dev/null || true
    sudo docker network prune -f 2>/dev/null || true
    docker container prune -f 2>/dev/null || true
    print_ok "Docker containers & networks removed"
}

clean_docker_network_state() {
    print_section "Docker Internal Network State"
    print_warn "Stopping Docker daemon, wiping /var/lib/docker/network/files, then restarting."
    print_step "Stopping Docker service..."
    sudo systemctl stop docker
    sudo systemctl stop docker.socket
    print_step "Wiping internal network state..."
    sudo rm -rf /var/lib/docker/network/files
    print_step "Starting Docker service..."
    sudo systemctl start docker
    print_ok "Docker internal network state wiped and service restarted"
}

clean_ports() {
    print_section "Port Cleanup"
    local PORTS=(3000 3001 30001 30002 30003)
    for port in "${PORTS[@]}"; do
        if sudo fuser -k "${port}/tcp" 2>/dev/null; then
            print_ok "Killed process on port ${port}"
        else
            print_step "Port ${port} — nothing listening"
        fi
    done

    echo ""
    print_step "Remaining listeners on target ports:"
    ss -lntp 2>/dev/null | grep -E '3000|3001|30001|30002|30003' \
        || print_ok "All target ports are free"
}

do_reboot() {
    print_section "System Reboot"
    echo ""
    echo -e "  ${BOLD}${YELLOW}System will reboot in 10 seconds.${RESET}"
    echo -e "  ${DIM}Press CTRL+C to cancel.${RESET}"
    echo ""
    sleep 10
    sudo reboot
}

maybe_restart_docker() {
    if [[ "$SEL_DOCKER_CONTAINERS" == true && "$SEL_DOCKER_NETWORK_STATE" != true ]]; then
        print_section "Docker Service Restart"
        print_step "Restarting Docker after container cleanup..."
        sudo systemctl restart docker
        print_ok "Docker restarted"
    fi
}

# MAIN
main() {
    while true; do
        select_services
        confirm_selection && break
    done

    clear
    print_header "Running Cleanup  --  Please Wait"

    [[ "$SEL_APP"                  == true ]] && clean_app
    [[ "$SEL_MONITORING"           == true ]] && clean_monitoring
    [[ "$SEL_LOKI"                 == true ]] && clean_loki
    [[ "$SEL_TRIVY"                == true ]] && clean_trivy
    [[ "$SEL_ARGOCD"               == true ]] && clean_argocd
    [[ "$SEL_GITLAB_RUNNER"        == true ]] && clean_gitlab_runner
    [[ "$SEL_KUBERNETES"           == true ]] && clean_kubernetes_workloads
    [[ "$SEL_MINIKUBE"             == true ]] && clean_minikube
    [[ "$SEL_DOCKER_CONTAINERS"    == true ]] && clean_docker_containers
    [[ "$SEL_DOCKER_NETWORK_STATE" == true ]] && clean_docker_network_state

    maybe_restart_docker

    [[ "$SEL_PORTS" == true ]] && clean_ports

    echo ""
    echo -e "${BOLD}${BRIGHT_CYAN}+============================================================================+${RESET}"
    echo -e "${BOLD}${BRIGHT_CYAN}|${RESET}  ${BOLD}${BRIGHT_GREEN}(+)  Cleanup Complete${RESET}  --  All selected components removed."
    echo -e "${BOLD}${BRIGHT_CYAN}+============================================================================+${RESET}"
    echo ""

    [[ "$SEL_REBOOT" == true ]] && do_reboot
}

main