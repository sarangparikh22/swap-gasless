// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import './interfaces/IERC20.sol';
import './interfaces/IWETH.sol';
import '@sushiswap/core/contracts/uniswapv2/libraries/TransferHelper.sol';
import './libraries/UniswapV2Library.sol';
import './libraries/SafeMath.sol';

contract GaslessSwap {
    using SafeMath for uint256;

    struct Swap {
        uint256 amountIn;
        uint256 amountOut;
        address[] path;
        address to;
        uint256 deadline;
    }
    
    address public immutable factory;
    address public immutable WETH;
    bytes32 public immutable pairCodeHash;
    
    address public owner;
    uint256 public feeToMinerPercent;
    
    modifier onlyOwner {
        require(msg.sender == owner, "GaslessSwap: !owner");
        _;
    }

    
    constructor(address _factory, address _weth, bytes32 _pairCodeHash, uint8 _feeToMiner) public {
        owner = msg.sender;
        factory = _factory;
        WETH = _weth;
        pairCodeHash = _pairCodeHash;
        feeToMinerPercent = _feeToMiner;
    }
    
    // Swap Logic
    
    function swapExactETHForTokens(Swap memory _swap, uint256 _fee) external payable {
        require(_swap.path[0] == WETH, 'GaslessSwap: Should be WETH');

        takeFees(_fee);
    
        uint amountIn = msg.value.sub(_fee);
        
        IWETH(WETH).deposit{value: amountIn}();
        
        IWETH(WETH).transfer(UniswapV2Library.pairFor(factory, _swap.path[0], _swap.path[1], pairCodeHash), amountIn);
        
        uint256[] memory amounts = UniswapV2Library.getAmountsOut(factory, amountIn, _swap.path, pairCodeHash);
        uint256 amountOut = amounts[amounts.length - 1];
        require(amountOut >= _swap.amountOut, "GaslessSwap: Insufficient Amount Out");

        _swapTokens(amounts, _swap.path, _swap.to);
    }
    
    function swapExactTokensForETH(Swap calldata _swap, uint256 _fee) external payable {
    
        require(_swap.path[_swap.path.length - 1] == WETH, 'GaslessSwap: Should be WETH');
        
        TransferHelper.safeTransferFrom(
          _swap.path[0], msg.sender, UniswapV2Library.pairFor(factory, _swap.path[0], _swap.path[1], pairCodeHash), _swap.amountIn
        );
        
        uint256[] memory amounts = UniswapV2Library.getAmountsOut(factory, _swap.amountIn, _swap.path, pairCodeHash);

        _swapTokens(amounts, _swap.path, address(this));
        
        uint amountOut = IERC20(WETH).balanceOf(address(this));
        
        require(amountOut >= _swap.amountOut, "GaslessSwap: Insufficient Amount Out");
        
        IWETH(WETH).withdraw(amountOut);
    
        takeFees(_fee);
      
        TransferHelper.safeTransferETH(_swap.to, amountOut - _fee);
    }
    
    function swapExactTokensForTokens(Swap calldata _swap, uint256 _fee) external payable {
        
        takeFees(_fee);
    
        TransferHelper.safeTransferFrom(
          _swap.path[0], msg.sender, UniswapV2Library.pairFor(factory, _swap.path[0], _swap.path[1], pairCodeHash), _swap.amountIn
        );
        
        uint256[] memory amounts = UniswapV2Library.getAmountsOut(factory, _swap.amountIn, _swap.path, pairCodeHash);
        uint256 amountOut = amounts[amounts.length - 1];
        require(amountOut >= _swap.amountOut, "GaslessSwap: Insufficient Amount Out");
        
        _swapTokens(amounts, _swap.path, _swap.to);
    }
    
    function swapExactTokensForTokensWithETH(Swap calldata _swap, uint256 _fee, address[] memory _ethPath) external payable {
        
        require(_swap.path[0] == _ethPath[0], 'GaslessSwap: Path not same');
        require(_ethPath[_ethPath.length - 1] == WETH, 'GaslessSwap: Should be WETH');
        
        uint256[] memory amounts = UniswapV2Library.getAmountsIn(factory, _fee, _ethPath, pairCodeHash);
        
        TransferHelper.safeTransferFrom(
          _ethPath[0], msg.sender, UniswapV2Library.pairFor(factory, _ethPath[0], _ethPath[1], pairCodeHash), amounts[0]
        );
        
        _swapTokens(amounts, _ethPath, address(this));
        
        IWETH(WETH).withdraw(_fee);

        takeFees(_fee);
        
        uint256 amountIn = _swap.amountIn.sub(amounts[0]);
        
        TransferHelper.safeTransferFrom(
          _swap.path[0], msg.sender, UniswapV2Library.pairFor(factory, _swap.path[0], _swap.path[1], pairCodeHash), amountIn
        );
        
        amounts = UniswapV2Library.getAmountsOut(factory, amountIn, _swap.path, pairCodeHash);
        uint256 amountOut = amounts[amounts.length - 1];
        require(amountOut >= _swap.amountOut, "GaslessSwap: Insufficient Amount Out");
        
        _swapTokens(amounts, _swap.path, _swap.to);
    }
    
    function _swapTokens(uint256[] memory amounts, address[] memory path, address _to) internal virtual {
        for (uint256 i; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);
            (address token0, ) = UniswapV2Library.sortTokens(input, output);
            uint256 amountOut = amounts[i + 1];
            (uint256 amount0Out, uint256 amount1Out) = input == token0
                ? (uint256(0), amountOut)
                : (amountOut, uint256(0));
            address to = i < path.length - 2 ? UniswapV2Library.pairFor(factory, output, path[i + 2], pairCodeHash) : _to;
            IUniswapV2Pair(UniswapV2Library.pairFor(factory, input, output, pairCodeHash)).swap(
                amount0Out,
                amount1Out,
                to,
                new bytes(0)
            );
        }
    }
    

    function takeFees(uint256 _fee) public payable {
        require(_fee > 0, "GaslessSwap: Fee musn't be 0");
        uint256 feeForMiner = _fee.mul(feeToMinerPercent).div(100);
        block.coinbase.transfer(feeForMiner);
    }
    
    
    function swipeFees(address payable _to, uint256 _amount) external onlyOwner {
        _to.transfer(_amount);
    }
    
    function changeFeePercent(uint256 _fee) external onlyOwner {
        feeToMinerPercent = _fee;
    }
    
    receive() external payable {}
}