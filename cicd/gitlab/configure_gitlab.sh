#!/usr/bin/env bash
# ============================================================================
# /cicd/gitlab/configure_gitlab.sh
# Description: Guides the user to commit code and register a GitLab Runner
# ============================================================================

# Resolve PROJECT_ROOT only if not already defined
if [[ -z "${PROJECT_ROOT:-}" ]]; then
    PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fi
source "${PROJECT_ROOT}/lib/bootstrap.sh"

configure_gitlab () {
    echo ""
    echo "╔════════════════════════════════════════════════════════════════════════════╗"
    echo "║                      🚀 GITLAB CI/CD SETUP GUIDE                           ║"
    echo "╚════════════════════════════════════════════════════════════════════════════╝"
    echo ""
    
    # Auto-detect project root (two levels up from this script)
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    
    cd "$PROJECT_ROOT" || { 
        echo -e "${RED}❌ Cannot cd to project root: $PROJECT_ROOT${RESET}"
        return 1
    }
    
    if [ ! -d .git ]; then
        echo -e "${YELLOW}⚠️  Not a Git repository. Skipping GitLab CI/CD setup.${RESET}"
        return 0
    fi
    
    # Git Status and Commit
    echo "╔════════════════════════════════════════════════════════════════════════════╗"
    echo "║                    STEP 1️⃣  GIT REPOSITORY STATUS                          ║"
    echo "╚════════════════════════════════════════════════════════════════════════════╝"
    echo ""
    git status
    echo ""
    echo "  ┌────────────────────────────────────────────────────────────────────────┐"
    echo "  │  ⚡ COMMIT CHANGES (If changes exist)                                  │"
    echo "  ├────────────────────────────────────────────────────────────────────────┤"
    echo "  │                                                                        │"
    echo "  │     \$ git add .                                                       │"
    echo "  │     \$ git commit -m 'Your commit message'                             │"
    echo "  │                                                                        │"
    echo "  └────────────────────────────────────────────────────────────────────────┘"
    echo ""
    echo "  ┌────────────────────────────────────────────────────────────────────────┐"
    echo "  │  ⚡ PUSH TO GITLAB                                                     │"
    echo "  ├────────────────────────────────────────────────────────────────────────┤"
    echo "  │                                                                        │"
    echo "  │     \$ git push gitlab main                                            │"
    echo "  │                                                                        │"
    echo "  └────────────────────────────────────────────────────────────────────────┘"
    echo ""
    echo_separator
    echo ""
    
    # Register GitLab Runner
    echo "╔════════════════════════════════════════════════════════════════════════════╗"
    echo "║              STEP 2️⃣  REGISTER GITLAB RUNNER (Docker Executor)             ║"
    echo "╚════════════════════════════════════════════════════════════════════════════╝"
    echo ""
    echo "  Follow the interactive prompts with this command:"
    echo ""
    echo "  ┌────────────────────────────────────────────────────────────────────────┐"
    echo "  │  ⚡ RUNNER REGISTRATION COMMAND                                        │"
    echo "  ├────────────────────────────────────────────────────────────────────────┤"
    echo "  │                                                                        │"
    echo "  │     \$ sudo gitlab-runner register \\                                  │"
    echo "  │         --url https://gitlab.com/ \\                                   │"
    echo "  │         --registration-token <YOUR_REGISTRATION_TOKEN> \\              │"
    echo "  │         --executor docker \\                                           │"
    echo "  │         --docker-image ubuntu:22.04 \\                                 │"
    echo "  │         --description 'devops-runner' \\                               │"
    echo "  │         --tag-list 'devops,ci' \\                                      │"
    echo "  │         --run-untagged='false'                                         │"
    echo "  │                                                                        │"
    echo "  └────────────────────────────────────────────────────────────────────────┘"
    echo ""
    echo_separator
    echo ""
    
    # Start GitLab Runner
    echo "╔════════════════════════════════════════════════════════════════════════════╗"
    echo "║                    STEP 3️⃣  START GITLAB RUNNER                            ║"
    echo "╚════════════════════════════════════════════════════════════════════════════╝"
    echo ""
    echo "  ┌────────────────────────────────────────────────────────────────────────┐"
    echo "  │  ⚡ START RUNNER COMMAND                                               │"
    echo "  ├────────────────────────────────────────────────────────────────────────┤"
    echo "  │                                                                        │"
    echo "  │     \$ sudo gitlab-runner start                                        │"
    echo "  │                                                                        │"
    echo "  └────────────────────────────────────────────────────────────────────────┘"
    echo ""
    echo "  ┌────────────────────────────────────────────────────────────────────────┐"
    echo "  │  📋 VERIFY RUNNER STATUS                                               │"
    echo "  ├────────────────────────────────────────────────────────────────────────┤"
    echo "  │                                                                        │"
    echo "  │     \$ sudo gitlab-runner status                                       │"
    echo "  │                                                                        │"
    echo "  └────────────────────────────────────────────────────────────────────────┘"
    echo ""
    echo_separator
    echo ""
    
    # Verify in GitLab UI
    echo "╔════════════════════════════════════════════════════════════════════════════╗"
    echo "║                  STEP 4️⃣  VERIFY RUNNER IN GITLAB UI                       ║"
    echo "╚════════════════════════════════════════════════════════════════════════════╝"
    echo ""
    echo "  ┌───────────────────────────────────────────────────────────────────────┐"
    echo "  │  🌐 GITLAB RUNNER VERIFICATION STEPS                                  │"
    echo "  ├───────────────────────────────────────────────────────────────────────┤"
    echo "  │                                                                       │"
    echo "  │  1. Open your GitLab project in browser                               │"
    echo "  │                                                                       │"
    echo "  │  2. Navigate to:                                                      │"
    echo "  │     Settings → CI/CD → Runners                                        │"
    echo "  │                                                                       │"
    echo "  │  3. Verify runner is listed as 'active' with tags:                    │"
    echo "  │     ✓ devops                                                          │"
    echo "  │     ✓ ci                                                              │"
    echo "  │                                                                       │"
    echo "  └───────────────────────────────────────────────────────────────────────┘"
    echo ""
    echo "  ┌───────────────────────────────────────────────────────────────────────┐"
    echo "  │  👉 GITLAB PROJECT URL                                                │"
    echo "  ├───────────────────────────────────────────────────────────────────────┤"
    echo "  │                                                                       │"
    echo "  │     https://gitlab.com/<your-username>/<your-project>                 │"
    echo "  │                                                                       │"
    echo "  └───────────────────────────────────────────────────────────────────────┘"
    echo ""
    echo_separator
    echo ""
    
    # Success Message
    echo "╔════════════════════════════════════════════════════════════════════════════╗"
    echo "║                    ✅ GITLAB CI/CD SETUP COMPLETE!                         ║"
    echo "╚════════════════════════════════════════════════════════════════════════════╝"
    echo ""
    echo "  Your GitLab CI/CD runner is now configured and ready to use."
    echo ""
    echo "  📋 Next Steps:"
    echo "     • Push code changes to trigger pipeline"
    echo "     • Monitor pipeline execution in GitLab UI"
    echo "     • Check runner logs: sudo gitlab-runner logs"
    echo ""
    echo_separator
}

# Only run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    configure_gitlab
fi