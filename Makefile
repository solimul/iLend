include .env

RPC                 := https://eth-sepolia.g.alchemy.com/v2/SjLdkEhHuQOTcbPmu57Q_B12M8_smC-I
CHAIN               := 11155111
API_KEY             := TC2ICV8GXTZTI8XACVKMJRVGUF4P7VUIEZ
DEPLOYMENT_SCRIPT   := DeployILend.s.sol
ETH                 := 0xdd13E55209Fd76AfE204dBda4007C227904f0a81
USDC                := 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238

.PHONY: deploy verify libs all

deploy:
	@echo "Deploying to Sepolia..."
	forge script script/$(DEPLOYMENT_SCRIPT):DeployILend \
	  --rpc-url $(RPC) \
	  --broadcast \
	  --slow

libs:
	@echo "Deploying and verifying libraries..."
	bash ./deploy_libs.sh $(RPC) $(SEPOLIA_PRIVATE_KEY) $(API_KEY)

verify:
	@echo "Verifying contracts on Sepolia Etherscan..."
	bash ./verify.sh $(API_KEY) $(CHAIN) $(DEPLOYMENT_SCRIPT) $(SEPOLIA_PRIVATE_KEY) $(USDC) $(ETH)

all: libs deploy verify
	@echo "Deploy + verify complete!"