set -o allexport; source ./.env; set +o allexport;

export NODE_OPTIONS="--max-old-space-size=15120"
export $(grep -v '^#' .env | xargs -d '\n')
npx hardhat node --fork $ETH_KOVAN_PROVIDER
