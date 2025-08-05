include .env

RPC                 := https://eth-sepolia.g.alchemy.com/v2/SjLdkEhHuQOTcbPmu57Q_B12M8_smC-I
CHAIN               := 11155111
API_KEY             := TC2ICV8GXTZTI8XACVKMJRVGUF4P7VUIEZ
DEPLOYMENT_SCRIPT   := DeployILend.s.sol
ETH                 := 0xdd13E55209Fd76AfE204dBda4007C227904f0a81
USDC                := 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238
PRICE_FEED          := 0x694AA1769357215DE4FAC081bf1f309aDC325306

# Format: CONTRACT_TO_LIBS = "contract1:lib1,lib2 contract2:lib3 contract3:"
CONTRACT_TO_LIBS := \
	"Params:" \
	"Treasury:" \
	"Collateral:PriceConverterLib" \
	"Deposit:" \
	"Borrow:PriceConverterLib" \
	"Payback:" \
	"LiquidationRegistry:" \
	"Monitor:PriceConverterLib" \
	"LiquidationEngine:" \
	"iLend:RevertLib"

CONTRACT_TO_PATH := \
	"Collateral:src/collateral/Collateral.sol" \
	"Borrow:src/borrow/Borrow.sol" \
	"Deposit:src/deposit/Deposit.sol" \
	"Payback:src/repayment/Payback.sol" \
	"Monitor:src/liquidation/Monitor.sol" \
	"LiquidationEngine:src/liquidation/LiquidationEngine.sol" \
	"LiquidationRegistry:src/liquidation/LiquidationRegistry.sol" \
	"Params:src/misc/Params.sol" \
	"Treasury:src/treasury/Treasury.sol" \
	"iLend:src/iLend.sol"



.PHONY: deploy verify libs all

deploy:
	forge script script/$(DEPLOYMENT_SCRIPT):DeployILend \
	  --rpc-url $(RPC) \
	  --broadcast 

libs:
	@echo "Deploying and verifying libraries..."
	bash ./deploy_libs.sh $(RPC) $(SEPOLIA_PRIVATE_KEY) $(API_KEY)

verify:
	@echo "Verifying contracts on Sepolia Etherscan..."
	bash ./verify.sh $(API_KEY) $(CHAIN) $(DEPLOYMENT_SCRIPT) $(SEPOLIA_PRIVATE_KEY) $(USDC) $(ETH) $(PRICE_FEED) $(CONTRACT_TO_LIBS)

all: libs deploy verify
	@echo "✅ Deploy + verify complete!"
