// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;
pragma abicoder v2;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import '@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol';
import '@uniswap/v3-core/contracts/libraries/TickMath.sol';
import '@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol';
import '@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol';
import '@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol';
import '@uniswap/v3-periphery/contracts/base/LiquidityManagement.sol';

contract FT is ERC20, Pausable, Ownable {

    //对代币合约地址和池费用等级进行硬编码
    address public constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    uint24 public constant poolFee = 3000;

    //声明一个不可变的公共变量 类型
    INonfungiblePositionManager public immutable nonfungiblePositionManager;

    //一个结构体
    //每个NFT都由ERC20智能合约中唯一的uint256 ID标识，声明为tokenId
    //要允许存入ERC20流动性表达式，创建一个名为Deposit的结构体
    struct Deposit {
        address owner;
        uint128 liquidity;
        address token0;
        address token1;
    }
    //上诉结构体的映射
    mapping(uint256 => Deposit) public deposits;

    //构造函数对不可替代的位置管理器接口、V3 router和periphery immutable构造函数的地址进行硬编码
    constructor(
        INonfungiblePositionManager _nonfungiblePositionManager
    ) {
        nonfungiblePositionManager = _nonfungiblePositionManager;
    }

    // 允许合约托管ERC20代币
    function onERC721Received(
        address operator,
        address,
        uint256 tokenId,
        bytes calldata
    ) external override returns (bytes4) {
        //获取位置信息
        _createDeposit(operator, tokenId);
        return this.onERC721Received.selector;
    }
    //向映射中添加实例，创建一个内部函数
    function _createDeposit(address owner, uint256 tokenId) internal {
        (, , address token0, address token1, , , , uint128 liquidity, , , , ) =
            nonfungiblePositionManager.positions(tokenId);
        // 设置位置的所有者和数据
        // 对操作者的要求：msg.sender
        deposits[tokenId] = Deposit({owner: owner, liquidity: liquidity, token0: token0, token1: token1});
    }

    //1. 增加/移出流动性 
    //1.1增加流动性
    //增加position的流动性，并进行调整以创建滑点保护
    /// @notice 在当前范围内增加流动性
    /// @dev 池必须已经初始化，以增加流动性
    /// @param tokenId ERC20代币的ID
    /// @param amount0 要添加的token0的数量
    /// @param amount1 要添加的token1的数量
    function increaseLiquidityCurrentRange(
        uint256 tokenId,
        uint256 amountAdd0,
        uint256 amountAdd1
    )
        external
        returns (
            uint128 liquidity,
            uint256 amount0,
            uint256 amount1
        )
    {
        INonfungiblePositionManager.IncreaseLiquidityParams memory params =
            INonfungiblePositionManager.IncreaseLiquidityParams({
                tokenId: tokenId,
                amount0Desired: amountAdd0,
                amount1Desired: amountAdd1,
                amount0Min: 0,
                amount1Min: 0,
                deadline: block.timestamp
            });

        (liquidity, amount0, amount1) = nonfungiblePositionManager.increaseLiquidity(params);
    }

    //1.2移除流动性
    /// @notice 使当前流动性减少一半的函数。一个例子来展示如何调用'递减流动性'函数定义在periphery.
    /// @param tokenId ERC20代币的ID
    /// @return amount0 token0收到的数量
    /// @return amount1 token1返回的数量
    function decreaseLiquidityInHalf(uint256 tokenId) external returns (uint256 amount0, uint256 amount1) {
        // 调用者必须为代币的主人
        require(msg.sender == deposits[tokenId].owner, 'Not the owner');
        // 获取tokenId的流动性数据
        uint128 liquidity = deposits[tokenId].liquidity;
        uint128 halfLiquidity = liquidity / 2;

        // amount0Min and amount1Min 价格滑移检查
        // 如果燃烧后收到的金额不大于这些最小值，事务将失败
        INonfungiblePositionManager.DecreaseLiquidityParams memory params =
            INonfungiblePositionManager.DecreaseLiquidityParams({
                tokenId: tokenId,
                liquidity: halfLiquidity,
                amount0Min: 0,
                amount1Min: 0,
                deadline: block.timestamp
            });

        (amount0, amount1) = nonfungiblePositionManager.decreaseLiquidity(params);

        //send liquidity back to owner
        _sendToOwner(tokenId, amount0, amount1);
    }

    //2. 交易功能 30分

    /// @notice 将资金转移给NFT的所有者
    /// @param tokenId ERC20的ID
    /// @param amount0 token0的数量
    /// @param amount1 token1的数量
    function _sendToOwner(
        uint256 tokenId,
        uint256 amount0,
        uint256 amount1
    ) internal {
        // 获得合同所有者
        address owner = deposits[tokenId].owner;
        address token0 = deposits[tokenId].token0;
        address token1 = deposits[tokenId].token1;
        // 将收取的费用寄给所有者
        TransferHelper.safeTransfer(token0, owner, amount0);
        TransferHelper.safeTransfer(token1, owner, amount1);
    }

     /// @notice 将NFT转让给所有者
    /// @param tokenId ERC20的id
    function retrieveNFT(uint256 tokenId) external {
        // 钱必须是所有者的
        require(msg.sender == deposits[tokenId].owner, 'Not the owner');
        // 将所有权转让给原所有者
        nonfungiblePositionManager.safeTransferFrom(address(this), msg.sender, tokenId);
        //删除与tokenid相关的信息
        delete deposits[tokenId];
    }

    //3. 实现手续费功能，千分之三手续费 10分

    /// @notice 收取与提供流动性相关的费用
    /// @dev 合约必须持有erc20 token才能收取费用
    /// @param tokenId ERC20代币的ID
    /// @return amount0 以token0收取的费用金额
    /// @return amount1 在token1中收取的费用金额
    function collectAllFees(uint256 tokenId) external returns (uint256 amount0, uint256 amount1) {
        // 调用者必须拥有ERC20 position
        //调用safeTransfer将触发' onERC721Received '，它必须返回选择器，否则传输将失败
        nonfungiblePositionManager.safeTransferFrom(msg.sender, address(this), tokenId);
        //设置amount0Max和amount1Max为uint256Max收取所有费用
        //或者可以将收件人设置为msg.sender ,并避免' sendToOwner '中的另一个事务
        INonfungiblePositionManager.CollectParams memory params =
            INonfungiblePositionManager.CollectParams({
                tokenId: tokenId,
                recipient: address(this),
                amount0Max: type(uint128).max,
                amount1Max: type(uint128).max
            });
        (amount0, amount1) = nonfungiblePositionManager.collect(params);
        //返回给给拥有者
        _sendToOwner(tokenId, amount0, amount1);
    }

    //4. 实现滑点功能 15分
    function Slippage(uint256 tokenId) external returns (uint256 amount0, uint256 amount1) {
        bool temp;
        INonfungiblePositionManager.IncreaseLiquidityParams memory params =
            INonfungiblePositionManager.IncreaseLiquidityParams({
                tokenId: tokenId,
                amount0Desired: amountAdd0,
                amount1Desired: amountAdd1,
                amount0Min: 0,
                amount1Min: 0,
                deadline: block.timestamp
            });
        if(temp) {
            (liquidity, amount0, amount1) = nonfungiblePositionManager.increaseLiquidity(params);
        }
        (amount0, amount1) = nonfungiblePositionManager.decreaseLiquidity(params);        
    }


    //5. 实现部署脚本 15分



    uint8 public constant decimals = 18;
    uint  public totalSupply;
    mapping(address => uint) public balanceOf;
    mapping(address => mapping(address => uint)) public allowance;
    bytes32 public DOMAIN_SEPARATOR;
    // keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
    bytes32 public constant PERMIT_TYPEHASH = 0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9;
    mapping(address => uint) public nonces;
    event Approval(address indexed owner, address indexed spender, uint value);
    event Transfer(address indexed from, address indexed to, uint value);

    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}
    
    function mint(address account, uint256 amount) external onlyOwner {
        totalSupply = totalSupply.add(amount);
        balanceOf[account] = balanceOf[account].add(amount);
        emit Transfer(address(0), account, amount);
    }

    function burn(uint256 amount, uint256 amount) external {
        balanceOf[account] = balanceOf[account].sub(amount);
        totalSupply = totalSupply.sub(amount);
        emit Transfer(account, address(0), amount);
    }

    function _beforeTokenTransfer(address from, address to, uint256 amount) internal virtual override whenNotPaused {
        super._beforeTokenTransfer(from, to, amount);
    }
    
    function pause() external onlyOwner {
        _pause();
    }
    
    function unpause() external onlyOwner {
        _unpause();
    }
}
