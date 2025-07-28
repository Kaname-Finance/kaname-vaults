# forge clean
# forge build
source .env
forge script script/DeployVault.sol:DeployFullBases --broadcast --rpc-url ${MAINNET_RPC_URL} --verify --delay 5 --retries 30
forge script script/DeployVault.sol:DeployKanameLens --broadcast --rpc-url ${MAINNET_RPC_URL} --verify --delay 5 --retries 30