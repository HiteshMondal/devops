#!/usr/bin/env bash
# lib/logging.sh -- Structured logging primitives
# Requires: colors.sh to be sourced first
# Pure ASCII separators for maximum terminal compatibility.
# No Unicode box-drawing characters.

# SEPARATORS
_SEP_HEAVY="  ============================================================================"
_SEP_LIGHT="  ----------------------------------------------------------------------------"
_SEP_STAR="  ******************************************************************************"
_SEP_DASH="  ______________________________________________________________________________"

print_divider() {
    echo -e "${BOLD}${BLUE}${_SEP_HEAVY}${RESET}"
}

echo_separator() {
    echo -e "${BOLD}${BLUE}${_SEP_HEAVY}${RESET}"
}

print_thin_divider() {
    echo -e "${DIM}${_SEP_LIGHT}${RESET}"
}

# SECTION HEADERS
# Major section banner -- bold full-width = rules framing a centred title
print_section() {
    local title="$1"
    local icon="${2:->}"
    local width=78
    local pad="  "
    local label="${icon}  ${title}"
    local label_len=${#label}
    local left_fill=$(( (width - label_len - 2) / 2 ))
    local right_fill=$(( width - label_len - 2 - left_fill ))
    local left_bar=""
    local right_bar=""
    for ((i=0; i<left_fill; i++)); do left_bar+="="; done
    for ((i=0; i<right_fill; i++)); do right_bar+="="; done

    echo ""
    echo -e "${BOLD}${BRIGHT_CYAN}${_SEP_HEAVY}${RESET}"
    echo -e "${pad}${BOLD}${BRIGHT_CYAN}[${RESET}  ${BOLD}${BRIGHT_WHITE}${icon}  ${title}${RESET}  ${BOLD}${BRIGHT_CYAN}]${RESET}"
    echo -e "${BOLD}${BRIGHT_CYAN}${_SEP_HEAVY}${RESET}"
    echo ""
}

# Subsection -- yellow >> label with dim - rule underneath
print_subsection() {
    echo ""
    echo -e "  ${BOLD}${YELLOW}>>${RESET}  ${BOLD}${BRIGHT_YELLOW}$1${RESET}"
    echo -e "${DIM}${YELLOW}${_SEP_LIGHT}${RESET}"
}

# LOG LEVELS

print_step() {
    echo -e "  ${BOLD}${CYAN}  ->  ${RESET}$1"
}

print_success() {
    echo -e "  ${BOLD}${BG_GREEN}${BRIGHT_WHITE} OK ${RESET}  ${BRIGHT_GREEN}$1${RESET}"
}

print_info() {
    echo -e "  ${BOLD}${CYAN}[i]${RESET}  ${CYAN}$1${RESET}"
}

print_warning() {
    echo -e "  ${BOLD}${BG_YELLOW}${BLACK} !! ${RESET}  ${YELLOW}$1${RESET}"
}

print_error() {
    echo -e "  ${BOLD}${BG_RED}${BRIGHT_WHITE} XX ${RESET}  ${RED}$1${RESET}"
}

print_warn() {
    print_warning "$1"
}

# INLINE HELPERS

# Labelled URL
print_url() {
    local label="$1"
    local url="$2"
    echo -e "     ${DIM}${label}${RESET}  ${BOLD}${ACCENT_URL}${url}${RESET}"
}

# Shell command with optional label
print_cmd() {
    local label="$1"
    local cmd="$2"
    [[ -n "$label" ]] && echo -e "     ${DIM}${label}${RESET}"
    echo -e "     ${BOLD}${YELLOW}\$${RESET} ${ACCENT_CMD}${cmd}${RESET}"
}

# Key / value credential line
print_credential() {
    local label="$1"
    local value="$2"
    echo -e "     ${DIM}${label}${RESET}  ${BOLD}${ACCENT}${value}${RESET}"
}

# Checklist item
print_target() {
    echo -e "  ${BOLD}${BRIGHT_GREEN}(+)${RESET} $1"
}

# Aligned key = value config row
print_kv() {
    local label="$1"
    local value="$2"
    printf "  ${DIM}%-22s${RESET}  ${BOLD}${BRIGHT_WHITE}%s${RESET}\n" "${label}" "${value}"
}

print_deploy_summary() {
    echo ""
    print_divider
    echo -e "  ${BOLD}${WHITE}Deployment Configuration${RESET}"
    print_thin_divider
}

# ===========================================================================
# ACCESS INFO BOX
# ===========================================================================
#
# Pure ASCII bordered box with color-coded content sections.
# Top/bottom border uses = signs, inner separator uses - signs.
# Left edge uses | for a structured column feel.
#
# Usage: print_access_box "TITLE" "ICON_OR_PREFIX" "TYPE:content" ...
#
# Line types:
#   URL:LABEL:https://...      arrow + bold underlined URL
#   CMD:LABEL|command          $ prompt with bold orange command
#   CRED:Label:value           dim label + bold gold value
#   SEP:                       inner light -- rule
#   BLANK:                     empty padded line
#   TEXT:some note             dim prose line
#   NOTE:warning text          yellow [!] warning line

print_access_box() {
    local title="$1"
    local icon="$2"
    shift 2
    local lines=("$@")

    # Border characters (pure ASCII)
    local TOP="${BOLD}${BRIGHT_CYAN}+============================================================================+${RESET}"
    local BOT="${BOLD}${BRIGHT_CYAN}+============================================================================+${RESET}"
    local INNER="${DIM}${CYAN}|  --------------------------------------------------------------------------  |${RESET}"
    local EDGE_L="${BOLD}${BRIGHT_CYAN}|${RESET}"
    local EDGE_R="${BOLD}${BRIGHT_CYAN}|${RESET}"

    # Title bar
    local title_text="${icon}  ${title}"
    # Pad title line to fill width (78 chars inner)
    local inner_width=76
    local title_len=${#title_text}
    local pad_right=$(( inner_width - title_len - 2 ))
    local spaces=""
    for ((i=0; i<pad_right; i++)); do spaces+=" "; done

    echo ""
    echo -e "$TOP"
    echo -e "${EDGE_L}  ${BOLD}${BRIGHT_CYAN}${icon}${RESET}  ${BOLD}${BRIGHT_WHITE}${title}${RESET}${spaces}${EDGE_R}"
    echo -e "$BOT"
    echo -e "${EDGE_L}                                                                            ${EDGE_R}"

    for line in "${lines[@]}"; do
        local type="${line%%:*}"
        local rest="${line#*:}"

        case "$type" in
            URL)
                local lbl="${rest%%:*}"
                local url="${rest#*:}"
                echo -e "${EDGE_L}  ${DIM}${lbl}${RESET}                                                              ${EDGE_R}"
                echo -e "${EDGE_L}    ${BOLD}${BRIGHT_GREEN}-->  ${ACCENT_URL}${url}${RESET}"
                echo -e "${EDGE_L}                                                                            ${EDGE_R}"
                ;;
            CMD)
                local clbl="${rest%%|*}"
                local cmd="${rest#*|}"
                [[ -n "$clbl" && "$clbl" != "$cmd" ]] && \
                    echo -e "${EDGE_L}  ${DIM}${clbl}${RESET}"
                echo -e "${EDGE_L}    ${BOLD}${YELLOW}\$${RESET}  ${ACCENT_CMD}${cmd}${RESET}"
                echo -e "${EDGE_L}                                                                            ${EDGE_R}"
                ;;
            CRED)
                local clbl="${rest%%:*}"
                local cval="${rest#*:}"
                echo -e "${EDGE_L}  ${ACCENT_KEY}${clbl}${RESET}  ${BOLD}${ACCENT}${cval}${RESET}"
                ;;
            SEP)
                echo -e "${EDGE_L}                                                                            ${EDGE_R}"
                echo -e "$INNER"
                echo -e "${EDGE_L}                                                                            ${EDGE_R}"
                ;;
            BLANK)
                echo -e "${EDGE_L}                                                                            ${EDGE_R}"
                ;;
            TEXT)
                echo -e "${EDGE_L}  ${DIM}${rest}${RESET}"
                ;;
            NOTE)
                echo -e "${EDGE_L}  ${BOLD}${YELLOW}[!]${RESET}  ${YELLOW}${rest}${RESET}"
                ;;
            *)
                echo -e "${EDGE_L}  ${line}"
                ;;
        esac
    done

    echo -e "${EDGE_L}                                                                            ${EDGE_R}"
    echo -e "$BOT"
    echo ""
}

# Convenience wrapper: single URL box
print_url_box() {
    local title="$1"
    local url="$2"
    local note="${3:-}"
    local lines=("URL:${title}:${url}")
    [[ -n "$note" ]] && lines+=("NOTE:${note}")
    print_access_box "${title}" ">>" "${lines[@]}"
}

print_service_access() {
    local name="$1"
    local namespace="$2"
    local port="$3"
    local title="$4"

    local url
    url=$(get_service_url "$name" "$namespace" "$port")

    case "$url" in
        port-forward:*)
            local pf="${url#port-forward:}"
            print_access_box "$title" ">" \
                "NOTE:Service is ClusterIP — use port-forward" \
                "SEP:" \
                "CMD:Start port-forward:|kubectl port-forward svc/${name} ${pf}:${pf} -n ${namespace}" \
                "URL:Open UI:http://localhost:${pf}"
            ;;
        pending-loadbalancer)
            print_access_box "$title" ">" \
                "NOTE:LoadBalancer provisioning in progress" \
                "CMD:Check status:|kubectl get svc ${name} -n ${namespace}"
            ;;
        *)
            print_access_box "$title" ">" \
                "URL:${title}:${url}"
            ;;
    esac
}

require_command() {
    local cmd="$1"
    local install_hint="${2:-}"
    if ! command -v "$cmd" &>/dev/null; then
        print_error "Required command not found: ${BOLD}${cmd}${RESET}"
        [[ -n "$install_hint" ]] && print_info "Install: ${ACCENT_CMD}${install_hint}${RESET}"
        exit 1
    fi
}

require_env() {
    local var="$1"
    local hint="${2:-}"
    if [[ -z "${!var:-}" ]]; then
        print_error "Required environment variable not set: ${BOLD}${var}${RESET}"
        [[ -n "$hint" ]] && print_info "${hint}"
        exit 1
    fi
}

require_file() {
    local path="$1"
    local hint="${2:-}"
    if [[ ! -f "$path" ]]; then
        print_error "Required file not found: ${BOLD}${path}${RESET}"
        [[ -n "$hint" ]] && print_info "${hint}"
        exit 1
    fi
}

require_dir() {
    local path="$1"
    local hint="${2:-}"
    if [[ ! -d "$path" ]]; then
        print_error "Required directory not found: ${BOLD}${path}${RESET}"
        [[ -n "$hint" ]] && print_info "${hint}"
        exit 1
    fi
}

#  RANDOM NODEPORT 
random_nodeport() {
    if command -v shuf >/dev/null 2>&1; then
        shuf -i 30000-32767 -n 1
    else
        echo $(( (RANDOM % 2768) + 30000 ))
    fi
}

#  DOCKER IMAGE TAG FROM GIT 
set_image_tag_from_git() {
    if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        export DOCKER_IMAGE_TAG
        DOCKER_IMAGE_TAG="$(git rev-parse --short HEAD)"
    else
        export DOCKER_IMAGE_TAG="local-$(date +%s)"
    fi
}

#  KUSTOMIZE OVERLAY PATH RESOLVER 
resolve_overlay_name() {
    case "${DEPLOY_TARGET:-local}" in
        local)       echo "local" ;;
        prod|production) echo "prod" ;;
        *)
            print_error "Unknown DEPLOY_TARGET '${DEPLOY_TARGET}'. Valid values: local, prod"
            exit 1
            ;;
    esac
}

#  CI MODE 
detect_ci_mode() {
    if [[ "${CI:-false}" == "true" ]] \
    || [[ -n "${GITHUB_ACTIONS:-}" ]] \
    || [[ -n "${GITLAB_CI:-}" ]]; then
        echo "true"
    else
        echo "false"
    fi
}

#  INTERACTIVE CHECK 
is_interactive() {
    [[ -t 0 && -z "${CI:-}" ]]
}

#  SERVICE TYPE / INGRESS CLASS RESOLUTION 
resolve_k8s_service_config() {
    case "${K8S_DISTRIBUTION:-kubernetes}" in
        minikube|kind|microk8s)
            export K8S_SERVICE_TYPE="NodePort"
            export K8S_INGRESS_CLASS="nginx"
            export K8S_SUPPORTS_LOADBALANCER="false"
            export MONITORING_SERVICE_TYPE="NodePort"
            ;;
        k3s)
            export K8S_SERVICE_TYPE="NodePort"
            export K8S_INGRESS_CLASS="traefik"
            export K8S_SUPPORTS_LOADBALANCER="true"
            export MONITORING_SERVICE_TYPE="LoadBalancer"
            ;;
        eks)
            export K8S_SERVICE_TYPE="LoadBalancer"
            export K8S_INGRESS_CLASS="alb"
            export K8S_SUPPORTS_LOADBALANCER="true"
            export MONITORING_SERVICE_TYPE="LoadBalancer"
            ;;
        gke)
            export K8S_SERVICE_TYPE="LoadBalancer"
            export K8S_INGRESS_CLASS="gce"
            export K8S_SUPPORTS_LOADBALANCER="true"
            export MONITORING_SERVICE_TYPE="LoadBalancer"
            ;;
        aks)
            export K8S_SERVICE_TYPE="LoadBalancer"
            export K8S_INGRESS_CLASS="azure"
            export K8S_SUPPORTS_LOADBALANCER="true"
            export MONITORING_SERVICE_TYPE="LoadBalancer"
            ;;
        *)
            export K8S_SERVICE_TYPE="ClusterIP"
            export K8S_INGRESS_CLASS="nginx"
            export K8S_SUPPORTS_LOADBALANCER="false"
            export MONITORING_SERVICE_TYPE="ClusterIP"
            ;;
    esac
    : "${INGRESS_CLASS:=${K8S_INGRESS_CLASS}}"
    export INGRESS_CLASS
}

#  ACCESS URL RESOLUTION 
get_service_url() {
    local service_name="$1"
    local namespace="$2"
    local default_port="$3"

    case "${K8S_DISTRIBUTION:-kubernetes}" in
        minikube)
            if ! command -v minikube >/dev/null 2>&1; then
                echo "minikube-cli-missing"; return
            fi
            local ip node_port
            ip=$(minikube ip 2>/dev/null || echo "localhost")
            node_port=$(kubectl get svc "$service_name" -n "$namespace" \
                -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo "")
            [[ -n "$node_port" ]] && echo "http://$ip:$node_port" \
                                  || echo "port-forward:$default_port"
            ;;
        kind)
            local node_port
            node_port=$(kubectl get svc "$service_name" -n "$namespace" \
                -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo "")
            [[ -n "$node_port" ]] && echo "http://localhost:$node_port" \
                                  || echo "port-forward:$default_port"
            ;;
        k3s|microk8s)
            local external_ip node_ip node_port
            external_ip=$(kubectl get svc "$service_name" -n "$namespace" \
                -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
            if [[ -n "$external_ip" ]]; then
                echo "http://$external_ip:$default_port"; return
            fi
            node_ip=$(kubectl get nodes \
                -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' \
                2>/dev/null || echo "localhost")
            node_port=$(kubectl get svc "$service_name" -n "$namespace" \
                -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo "")
            [[ -n "$node_port" ]] && echo "http://$node_ip:$node_port" \
                                  || echo "port-forward:$default_port"
            ;;
        eks|gke|aks)
            local external_ip
            external_ip=$(kubectl get svc "$service_name" -n "$namespace" \
                -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || \
                kubectl get svc "$service_name" -n "$namespace" \
                -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
            [[ -n "$external_ip" ]] && echo "http://$external_ip:$default_port" \
                                    || echo "pending-loadbalancer"
            ;;
        *)
            local node_ip node_port
            node_ip=$(kubectl get nodes \
                -o jsonpath='{.items[0].status.addresses[?(@.type=="ExternalIP")].address}' \
                2>/dev/null || \
                kubectl get nodes \
                -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' \
                2>/dev/null || echo "localhost")
            node_port=$(kubectl get svc "$service_name" -n "$namespace" \
                -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo "")
            [[ -n "$node_port" ]] && echo "http://$node_ip:$node_port" \
                                  || echo "port-forward:$default_port"
            ;;
    esac
}

#  CONTAINER RUNTIME DETECTION 
detect_container_runtime() {
    if command -v docker >/dev/null 2>&1; then
        if ! docker info >/dev/null 2>&1; then
            print_error "Docker daemon is not accessible (permission issue)"
            print_cmd "Fix with:" "sudo usermod -aG docker $USER && newgrp docker"
            exit 1
        fi
        export CONTAINER_RUNTIME="docker"
    elif command -v podman >/dev/null 2>&1; then
        export CONTAINER_RUNTIME="podman"
    else
        print_error "Neither Docker nor Podman found"
        print_url "Install Docker:"  "https://docs.docker.com/get-docker/"
        print_url "Install Podman:"  "https://podman.io/getting-started/installation"
        exit 1
    fi
}