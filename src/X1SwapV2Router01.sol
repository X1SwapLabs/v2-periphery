pragma solidity =0.6.6;

import "@x1swap/v2-core/src/interfaces/IX1SwapV2Factory.sol";
import "@x1swap/lib/src/TransferHelper.sol";

import "./libraries/X1swapV2Library.sol";
import "./interfaces/IX1swapV2Router01.sol";
import "./interfaces/IERC20.sol";
import "./interfaces/IWETH.sol";

contract X1swapV2Router01 is IX1swapV2Router01 {
    address public immutable override factory;
    address public immutable override WETH;

    modifier ensure(uint256 deadline) {
        require(deadline >= block.timestamp, "X1swapV2Router: EXPIRED");
        _;
    }

    constructor(address _factory, address _WETH) public {
        factory = _factory;
        WETH = _WETH;
    }

    receive() external payable {
        assert(msg.sender == WETH); // only accept ETH via fallback from the WETH contract
    }

    // **** ADD LIQUIDITY ****
    function _addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin
    ) private returns (uint256 amountA, uint256 amountB) {
        // create the pair if it doesn't exist yet
        if (IX1SwapV2Factory(factory).getPair(tokenA, tokenB) == address(0)) {
            IX1SwapV2Factory(factory).createPair(tokenA, tokenB);
        }
        (uint256 reserveA, uint256 reserveB) = X1swapV2Library.getReserves(factory, tokenA, tokenB);
        if (reserveA == 0 && reserveB == 0) {
            (amountA, amountB) = (amountADesired, amountBDesired);
        } else {
            uint256 amountBOptimal = X1swapV2Library.quote(amountADesired, reserveA, reserveB);
            if (amountBOptimal <= amountBDesired) {
                require(amountBOptimal >= amountBMin, "X1swapV2Router: INSUFFICIENT_B_AMOUNT");
                (amountA, amountB) = (amountADesired, amountBOptimal);
            } else {
                uint256 amountAOptimal = X1swapV2Library.quote(amountBDesired, reserveB, reserveA);
                assert(amountAOptimal <= amountADesired);
                require(amountAOptimal >= amountAMin, "X1swapV2Router: INSUFFICIENT_A_AMOUNT");
                (amountA, amountB) = (amountAOptimal, amountBDesired);
            }
        }
    }

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external override ensure(deadline) returns (uint256 amountA, uint256 amountB, uint256 liquidity) {
        (amountA, amountB) = _addLiquidity(tokenA, tokenB, amountADesired, amountBDesired, amountAMin, amountBMin);
        address pair = X1swapV2Library.pairFor(factory, tokenA, tokenB);
        TransferHelper.safeTransferFrom(tokenA, msg.sender, pair, amountA);
        TransferHelper.safeTransferFrom(tokenB, msg.sender, pair, amountB);
        liquidity = IX1SwapV2Pair(pair).mint(to);
    }

    function addLiquidityETH(
        address token,
        uint256 amountTokenDesired,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) external payable override ensure(deadline) returns (uint256 amountToken, uint256 amountETH, uint256 liquidity) {
        (amountToken, amountETH) =
            _addLiquidity(token, WETH, amountTokenDesired, msg.value, amountTokenMin, amountETHMin);
        address pair = X1swapV2Library.pairFor(factory, token, WETH);
        TransferHelper.safeTransferFrom(token, msg.sender, pair, amountToken);
        IWETH(WETH).deposit{value: amountETH}();
        assert(IWETH(WETH).transfer(pair, amountETH));
        liquidity = IX1SwapV2Pair(pair).mint(to);
        if (msg.value > amountETH) TransferHelper.safeTransferETH(msg.sender, msg.value - amountETH); // refund dust eth, if any
    }

    // **** REMOVE LIQUIDITY ****
    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) public override ensure(deadline) returns (uint256 amountA, uint256 amountB) {
        address pair = X1swapV2Library.pairFor(factory, tokenA, tokenB);
        IX1SwapV2Pair(pair).transferFrom(msg.sender, pair, liquidity); // send liquidity to pair
        (uint256 amount0, uint256 amount1) = IX1SwapV2Pair(pair).burn(to);
        (address token0,) = X1swapV2Library.sortTokens(tokenA, tokenB);
        (amountA, amountB) = tokenA == token0 ? (amount0, amount1) : (amount1, amount0);
        require(amountA >= amountAMin, "X1swapV2Router: INSUFFICIENT_A_AMOUNT");
        require(amountB >= amountBMin, "X1swapV2Router: INSUFFICIENT_B_AMOUNT");
    }

    function removeLiquidityETH(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) public override ensure(deadline) returns (uint256 amountToken, uint256 amountETH) {
        (amountToken, amountETH) =
            removeLiquidity(token, WETH, liquidity, amountTokenMin, amountETHMin, address(this), deadline);
        TransferHelper.safeTransfer(token, to, amountToken);
        IWETH(WETH).withdraw(amountETH);
        TransferHelper.safeTransferETH(to, amountETH);
    }

    function removeLiquidityWithPermit(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline,
        bool approveMax,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external override returns (uint256 amountA, uint256 amountB) {
        address pair = X1swapV2Library.pairFor(factory, tokenA, tokenB);
        uint256 value = approveMax ? uint256(-1) : liquidity;
        IX1SwapV2Pair(pair).permit(msg.sender, address(this), value, deadline, v, r, s);
        (amountA, amountB) = removeLiquidity(tokenA, tokenB, liquidity, amountAMin, amountBMin, to, deadline);
    }

    function removeLiquidityETHWithPermit(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline,
        bool approveMax,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external override returns (uint256 amountToken, uint256 amountETH) {
        address pair = X1swapV2Library.pairFor(factory, token, WETH);
        uint256 value = approveMax ? uint256(-1) : liquidity;
        IX1SwapV2Pair(pair).permit(msg.sender, address(this), value, deadline, v, r, s);
        (amountToken, amountETH) = removeLiquidityETH(token, liquidity, amountTokenMin, amountETHMin, to, deadline);
    }

    // **** SWAP ****
    // requires the initial amount to have already been sent to the first pair
    function _swap(uint256[] memory amounts, address[] memory path, address _to) private {
        for (uint256 i; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);
            (address token0,) = X1swapV2Library.sortTokens(input, output);
            uint256 amountOut = amounts[i + 1];
            (uint256 amount0Out, uint256 amount1Out) =
                input == token0 ? (uint256(0), amountOut) : (amountOut, uint256(0));
            address to = i < path.length - 2 ? X1swapV2Library.pairFor(factory, output, path[i + 2]) : _to;
            IX1SwapV2Pair(X1swapV2Library.pairFor(factory, input, output)).swap(
                amount0Out, amount1Out, to, new bytes(0)
            );
        }
    }

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external override ensure(deadline) returns (uint256[] memory amounts) {
        amounts = X1swapV2Library.getAmountsOut(factory, amountIn, path);
        require(amounts[amounts.length - 1] >= amountOutMin, "X1swapV2Router: INSUFFICIENT_OUTPUT_AMOUNT");
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, X1swapV2Library.pairFor(factory, path[0], path[1]), amounts[0]
        );
        _swap(amounts, path, to);
    }

    function swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external override ensure(deadline) returns (uint256[] memory amounts) {
        amounts = X1swapV2Library.getAmountsIn(factory, amountOut, path);
        require(amounts[0] <= amountInMax, "X1swapV2Router: EXCESSIVE_INPUT_AMOUNT");
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, X1swapV2Library.pairFor(factory, path[0], path[1]), amounts[0]
        );
        _swap(amounts, path, to);
    }

    function swapExactETHForTokens(uint256 amountOutMin, address[] calldata path, address to, uint256 deadline)
        external
        payable
        override
        ensure(deadline)
        returns (uint256[] memory amounts)
    {
        require(path[0] == WETH, "X1swapV2Router: INVALID_PATH");
        amounts = X1swapV2Library.getAmountsOut(factory, msg.value, path);
        require(amounts[amounts.length - 1] >= amountOutMin, "X1swapV2Router: INSUFFICIENT_OUTPUT_AMOUNT");
        IWETH(WETH).deposit{value: amounts[0]}();
        assert(IWETH(WETH).transfer(X1swapV2Library.pairFor(factory, path[0], path[1]), amounts[0]));
        _swap(amounts, path, to);
    }

    function swapTokensForExactETH(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external override ensure(deadline) returns (uint256[] memory amounts) {
        require(path[path.length - 1] == WETH, "X1swapV2Router: INVALID_PATH");
        amounts = X1swapV2Library.getAmountsIn(factory, amountOut, path);
        require(amounts[0] <= amountInMax, "X1swapV2Router: EXCESSIVE_INPUT_AMOUNT");
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, X1swapV2Library.pairFor(factory, path[0], path[1]), amounts[0]
        );
        _swap(amounts, path, address(this));
        IWETH(WETH).withdraw(amounts[amounts.length - 1]);
        TransferHelper.safeTransferETH(to, amounts[amounts.length - 1]);
    }

    function swapExactTokensForETH(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external override ensure(deadline) returns (uint256[] memory amounts) {
        require(path[path.length - 1] == WETH, "X1swapV2Router: INVALID_PATH");
        amounts = X1swapV2Library.getAmountsOut(factory, amountIn, path);
        require(amounts[amounts.length - 1] >= amountOutMin, "X1swapV2Router: INSUFFICIENT_OUTPUT_AMOUNT");
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, X1swapV2Library.pairFor(factory, path[0], path[1]), amounts[0]
        );
        _swap(amounts, path, address(this));
        IWETH(WETH).withdraw(amounts[amounts.length - 1]);
        TransferHelper.safeTransferETH(to, amounts[amounts.length - 1]);
    }

    function swapETHForExactTokens(uint256 amountOut, address[] calldata path, address to, uint256 deadline)
        external
        payable
        override
        ensure(deadline)
        returns (uint256[] memory amounts)
    {
        require(path[0] == WETH, "X1swapV2Router: INVALID_PATH");
        amounts = X1swapV2Library.getAmountsIn(factory, amountOut, path);
        require(amounts[0] <= msg.value, "X1swapV2Router: EXCESSIVE_INPUT_AMOUNT");
        IWETH(WETH).deposit{value: amounts[0]}();
        assert(IWETH(WETH).transfer(X1swapV2Library.pairFor(factory, path[0], path[1]), amounts[0]));
        _swap(amounts, path, to);
        if (msg.value > amounts[0]) TransferHelper.safeTransferETH(msg.sender, msg.value - amounts[0]); // refund dust eth, if any
    }

    function quote(uint256 amountA, uint256 reserveA, uint256 reserveB)
        public
        pure
        override
        returns (uint256 amountB)
    {
        return X1swapV2Library.quote(amountA, reserveA, reserveB);
    }

    function getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut)
        public
        pure
        override
        returns (uint256 amountOut)
    {
        return X1swapV2Library.getAmountOut(amountIn, reserveIn, reserveOut);
    }

    function getAmountIn(uint256 amountOut, uint256 reserveIn, uint256 reserveOut)
        public
        pure
        override
        returns (uint256 amountIn)
    {
        return X1swapV2Library.getAmountOut(amountOut, reserveIn, reserveOut);
    }

    function getAmountsOut(uint256 amountIn, address[] memory path)
        public
        view
        override
        returns (uint256[] memory amounts)
    {
        return X1swapV2Library.getAmountsOut(factory, amountIn, path);
    }

    function getAmountsIn(uint256 amountOut, address[] memory path)
        public
        view
        override
        returns (uint256[] memory amounts)
    {
        return X1swapV2Library.getAmountsIn(factory, amountOut, path);
    }
}
