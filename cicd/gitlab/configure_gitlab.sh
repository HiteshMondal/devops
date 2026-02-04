#!/usr/bin/env bash
# ============================================================================
# /cicd/gitlab/configure_gitlab.sh
# Description: Guides the user to commit code and register a GitLab Runner
# ============================================================================

# Colors for formatting
GREEN="\033[1;32m"
YELLOW="\033[1;33m"
CYAN="\033[1;36m"
RESET="\033[0m"
BOLD="\033[1m"

echo_separator() {
  echo -e "${CYAN}===============================================================${RESET}"
}

configure_gitlab () {
  echo_separator
  echo -e "${BOLD}🚀 GitLab CI/CD Setup Guide${RESET}"
  echo_separator
  echo ""
  echo -e "${YELLOW}Step 1️⃣  Check your Git repository for changes${RESET}"
  git status
  echo -e "  - If changes exist, commit them:"
  echo -e "      ${GREEN}git add .${RESET}"
  echo -e "      ${GREEN}git commit -m 'Your commit message'${RESET}"
  echo -e "  - Then push to GitLab:"
  echo -e "      ${GREEN}git push gitlab main${RESET}"
  echo ""
  echo -e "${YELLOW}Step 2️⃣  Register a GitLab Runner (Docker executor)${RESET}"
  echo -e "  - Run the following command and follow interactive prompts:"
  echo -e "${GREEN}sudo gitlab-runner register \\"
  echo -e "  --url https://gitlab.com/ \\"
  echo -e "  --registration-token <YOUR_REGISTRATION_TOKEN> \\"
  echo -e "  --executor docker \\"
  echo -e "  --docker-image ubuntu:22.04 \\"
  echo -e "  --description 'devops-runner' \\"
  echo -e "  --tag-list 'devops,ci' \\"
  echo -e "  --run-untagged='false' \\"

  echo ""
  echo -e "${YELLOW}Step 3️⃣  Start the GitLab Runner${RESET}"
  echo -e "  - Run: ${GREEN}sudo gitlab-runner start${RESET}"
  echo ""
  echo -e "${YELLOW}Step 4️⃣  Verify Runner in GitLab${RESET}"
  echo -e "  1. Go to your GitLab project in a browser"
  echo -e "  2. Navigate to: Settings > CI/CD > Runners"
  echo -e "  3. Ensure your runner is listed as 'active' with tags: ${GREEN}devops, ci${RESET}"
  echo ""
  echo -e "${BOLD}✅ All steps completed! Your GitLab CI/CD runner should now be ready.${RESET}"
  echo_separator
}

# Only run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  configure_gitlab
fi
