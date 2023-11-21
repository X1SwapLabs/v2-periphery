include ../.env
export 

WOKB=0xa2aFfd8301BfB3c5b815829f2F509f053556D21B
FACTORY=0x042a5098940ccbd0a4c06418c2f4e9ebf055c4f7

create_X1SwapV2Factory:
	forge create --rpc-url $(X1_TESTNET) \
		--private-key $(PRIVATE_KEY) \
		--constructor-args $(FACTORY) $(WOKB) \
		--legacy \
		src/X1swapV2Router02.sol:X1swapV2Router02