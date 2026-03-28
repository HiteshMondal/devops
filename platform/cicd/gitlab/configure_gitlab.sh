#!/usr/bin/env bash
# /cicd/gitlab/configure_gitlab.sh
# Description: Guides the user to commit code and register a GitLab Runner

# Resolve PROJECT_ROOT only if not already defined
if [[ -z "${PROJECT_ROOT:-}" ]]; then
    PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fi
source "${PROJECT_ROOT}/platform/lib/bootstrap.sh"

configure_gitlab () {
    echo ""
    print_section "GITLAB CI/CD SETUP GUIDE" "+"

    # Auto-detect project root (two levels up from this script)
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

    cd "$PROJECT_ROOT" || {
        echo -e "${RED}  [x]  Cannot cd to project root: $PROJECT_ROOT${RESET}"
        return 1
    }

    if [ ! -d .git ]; then
        print_warning "Not a Git repository. Skipping GitLab CI/CD setup."
        return 0
    fi

    print_subsection "STEP 1  --  GIT REPOSITORY STATUS"
    echo ""
    git status
    echo ""

    print_access_box "COMMIT & PUSH CHANGES" "+" \
        "NOTE:Stage and commit any pending changes before pushing" \
        "BLANK:" \
        "CMD:Stage all changes:|git add ." \
        "CMD:Commit with message:|git commit -m 'Your commit message'" \
        "SEP:" \
        "NOTE:Push your branch to GitLab to trigger the pipeline" \
        "BLANK:" \
        "CMD:Push to GitLab main:|git push gitlab main"

    echo_separator

    print_subsection "STEP 2  --  REGISTER GITLAB RUNNER  (Docker Executor)"
    echo ""

    print_access_box "RUNNER REGISTRATION COMMAND" "+" \
        "NOTE:Follow the interactive prompts after running this command" \
        "BLANK:" \
        "CMD:Register GitLab Runner:|sudo gitlab-runner register \\" \
        "CMD:|    --url https://gitlab.com/ \\" \
        "CMD:|    --registration-token <YOUR_REGISTRATION_TOKEN> \\" \
        "CMD:|    --executor docker \\" \
        "CMD:|    --docker-image ubuntu:22.04 \\" \
        "CMD:|    --description 'devops-runner' \\" \
        "CMD:|    --tag-list 'devops,ci' \\" \
        "CMD:|    --run-untagged='false'"

    echo_separator

    print_subsection "STEP 3  --  START GITLAB RUNNER"
    echo ""

    print_access_box "START & VERIFY RUNNER" "+" \
        "CMD:Start the runner:|sudo gitlab-runner start" \
        "BLANK:" \
        "CMD:Check runner status:|sudo gitlab-runner status"

    echo_separator

    print_subsection "STEP 4  --  VERIFY RUNNER IN GITLAB UI"
    echo ""

    print_access_box "GITLAB UI VERIFICATION STEPS" "+" \
        "NOTE:Open your GitLab project in a browser and navigate to:" \
        "TEXT:  Settings  ->  CI/CD  ->  Runners" \
        "BLANK:" \
        "NOTE:Confirm the runner is listed as active with both tags:" \
        "CRED:Tag 1:devops" \
        "CRED:Tag 2:ci" \
        "SEP:" \
        "URL:Your GitLab Project:https://gitlab.com/<your-username>/<your-project>"

    echo_separator

    print_section "GITLAB CI/CD SETUP COMPLETE" "+"
    echo ""
    print_success "GitLab Runner is configured and ready to process pipelines."
    echo ""
    print_info "Next steps:"
    print_step "Push code changes to trigger the pipeline"
    print_step "Monitor pipeline execution in the GitLab UI"
    print_step "Check runner logs:  sudo gitlab-runner logs"
    echo ""
    echo_separator
}

# Only run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    configure_gitlab
fi