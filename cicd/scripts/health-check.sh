# File: scripts/health-check.sh
#!/bin/bash
set -euo pipefail

URL="${1:-http://localhost:3000}"
MAX_ATTEMPTS="${2:-30}"
WAIT_TIME="${3:-10}"

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

echo "Health checking: ${URL}"
echo "Max attempts: ${MAX_ATTEMPTS}"
echo "Wait time between attempts: ${WAIT_TIME}s"
echo "-----------------------------------"

for i in $(seq 1 ${MAX_ATTEMPTS}); do
    echo "Attempt ${i}/${MAX_ATTEMPTS}..."
    
    # Check health endpoint
    if curl -sf "${URL}/health" > /dev/null 2>&1; then
        echo -e "${GREEN}✓ Health check passed${NC}"
        
        # Additional checks
        if curl -sf "${URL}/health/ready" > /dev/null 2>&1; then
            echo -e "${GREEN}✓ Readiness check passed${NC}"
        fi
        
        if curl -sf "${URL}/health/live" > /dev/null 2>&1; then
            echo -e "${GREEN}✓ Liveness check passed${NC}"
        fi
        
        echo -e "${GREEN}All health checks passed!${NC}"
        exit 0
    else
        echo -e "${RED}✗ Health check failed${NC}"
        if [ ${i} -lt ${MAX_ATTEMPTS} ]; then
            echo "Waiting ${WAIT_TIME}s before retry..."
            sleep ${WAIT_TIME}
        fi
    fi
done

echo -e "${RED}Health check failed after ${MAX_ATTEMPTS} attempts${NC}"
exit 1
