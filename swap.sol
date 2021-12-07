pragma solidity 0.8.6;     
// SPDX-License-Identifier: UNLICENSED 

abstract contract ReentrancyGuard {

    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;

    uint256 private _status;

    constructor () {
        _status = _NOT_ENTERED;
    }

    modifier nonReentrant() {

        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");

        _status = _ENTERED;

        _;

        _status = _NOT_ENTERED;
    }
}

contract FConst is ReentrancyGuard {
    uint public constant BASE              = 10**18;

    uint public tx1; //Token tx fee
    uint public tx2; //Main tx fee

    uint public constant MIN_BPOW_BASE     = 1 wei;
    uint public constant MAX_BPOW_BASE     = (2 * BASE) - 1 wei;
    uint public constant BPOW_PRECISION    = BASE / 10**10;

}


contract FNum is ReentrancyGuard, FConst {

    function btoi(uint a)
        internal pure
        returns (uint)
    {
        return a / BASE;
    }

    function bfloor(uint a)
        internal pure
        returns (uint)
    {
        return btoi(a) * BASE;
    }

    function badd(uint a, uint b)
        internal pure
        returns (uint)
    {
        uint c = a + b;
        require(c >= a, "ERR_ADD_OVERFLOW");
        return c;
    }

    function bsub(uint a, uint b)
        internal pure
        returns (uint)
    {
        (uint c, bool flag) = bsubSign(a, b);
        require(!flag, "ERR_SUB_UNDERFLOW");
        return c;
    }

    function bsubSign(uint a, uint b)
        internal pure
        returns (uint, bool)
    {
        if (a >= b) {
            return (a - b, false);
        } else {
            return (b - a, true);
        }
    }

    function bmul(uint a, uint b)
        internal pure
        returns (uint)
    {
        uint c0 = a * b;
        require(a == 0 || c0 / a == b, "ERR_MUL_OVERFLOW");
        uint c1 = c0 + (BASE / 2);
        require(c1 >= c0, "ERR_MUL_OVERFLOW");
        uint c2 = c1 / BASE;
        return c2;
    }

    function bdiv(uint a, uint b)
        internal pure
        returns (uint)
    {
        require(b != 0, "ERR_DIV_ZERO");
        uint c0 = a * BASE;
        require(a == 0 || c0 / a == BASE, "ERR_DIV_INTERNAL"); // bmul overflow
        uint c1 = c0 + (b / 2);
        require(c1 >= c0, "ERR_DIV_INTERNAL"); //  badd require
        uint c2 = c1 / b;
        return c2;
    }

    function bpowi(uint a, uint n)
        internal pure
        returns (uint)
    {
        uint z = n % 2 != 0 ? a : BASE;

        for (n /= 2; n != 0; n /= 2) {
            a = bmul(a, a);

            if (n % 2 != 0) {
                z = bmul(z, a);
            }
        }
        return z;
    }

    function bpow(uint base, uint exp)
        internal pure
        returns (uint)
    {
        require(base >= MIN_BPOW_BASE, "ERR_BPOW_BASE_TOO_LOW");
        require(base <= MAX_BPOW_BASE, "ERR_BPOW_BASE_TOO_HIGH");

        uint whole  = bfloor(exp);
        uint remain = bsub(exp, whole);

        uint wholePow = bpowi(base, btoi(whole));

        if (remain == 0) {
            return wholePow;
        }

        uint partialResult = bpowApprox(base, remain, BPOW_PRECISION);
        return bmul(wholePow, partialResult);
    }

    function bpowApprox(uint base, uint exp, uint precision)
        internal pure
        returns (uint)
    {
        uint a     = exp;
        (uint x, bool xneg)  = bsubSign(base, BASE);
        uint term = BASE;
        uint sum   = term;
        bool negative = false;


        for (uint i = 1; term >= precision; i++) {
            uint bigK = i * BASE;
            (uint c, bool cneg) = bsubSign(a, bsub(bigK, BASE));
            term = bmul(term, bmul(c, x));
            term = bdiv(term, bigK);
            if (term == 0) break;

            if (xneg) negative = !negative;
            if (cneg) negative = !negative;
            if (negative) {
                sum = bsub(sum, term);
            } else {
                sum = badd(sum, term);
            }
        }

        return sum;
    }
}

contract FMath is FConst, FNum {
    
        function calcSpotPrice(
        uint tokenBalanceIn,
        uint tokenWeightIn,
        uint tokenBalanceOut,
        uint tokenWeightOut,
        uint swapFee
    )
        public pure
        returns (uint spotPrice)
    {
        uint numer = bdiv(tokenBalanceIn, tokenWeightIn);
        uint denom = bdiv(tokenBalanceOut, tokenWeightOut);
        uint ratio = bdiv(numer, denom);
        uint scale = bdiv(BASE, bsub(BASE, swapFee));
        return  (spotPrice = bmul(ratio, scale));
    }


    function calcOutGivenIn(
        uint tokenBalanceIn,
        uint tokenWeightIn,
        uint tokenBalanceOut,
        uint tokenWeightOut,
        uint tokenAmountIn,
        uint swapFee
    )
        public pure
        returns (uint tokenAmountOut, uint tokenInFee)
    {
        uint weightRatio = bdiv(tokenWeightIn, tokenWeightOut);
        uint adjustedIn = bsub(BASE, swapFee);
        adjustedIn = bmul(tokenAmountIn, adjustedIn);
        uint y = bdiv(tokenBalanceIn, badd(tokenBalanceIn, adjustedIn));
        uint foo = bpow(y, weightRatio);
        uint bar = bsub(BASE, foo);
        tokenAmountOut = bmul(tokenBalanceOut, bar);
        tokenInFee = bsub(tokenAmountIn, adjustedIn);
        return (tokenAmountOut, tokenInFee);
    }


    function calcInGivenOut(
        uint tokenBalanceIn,
        uint tokenWeightIn,
        uint tokenBalanceOut,
        uint tokenWeightOut,
        uint tokenAmountOut,
        uint swapFee
    )
        public pure
        returns (uint tokenAmountIn, uint tokenInFee)
    {
        uint weightRatio = bdiv(tokenWeightOut, tokenWeightIn);
        uint diff = bsub(tokenBalanceOut, tokenAmountOut);
        uint y = bdiv(tokenBalanceOut, diff);
        uint foo = bpow(y, weightRatio);
        foo = bsub(foo, BASE);
        foo = bmul(tokenBalanceIn, foo);
        tokenAmountIn = bsub(BASE, swapFee);
        tokenAmountIn = bdiv(foo, tokenAmountIn);
        tokenInFee = bdiv(foo, BASE);
        tokenInFee = bsub(tokenAmountIn, tokenInFee);
        return (tokenAmountIn, tokenInFee);
    }

    function calcPoolOutGivenSingleIn(
        uint tokenBalanceIn,
        uint tokenWeightIn,
        uint poolSupply,
        uint totalWeight,
        uint tokenAmountIn,
        uint swapFee,
        uint reservesRatio
    )
        public pure
        returns (uint poolAmountOut, uint reserves)
    {

        uint normalizedWeight = bdiv(tokenWeightIn, totalWeight);
         uint zaz = bmul(bsub(BASE, normalizedWeight), swapFee);
        uint tokenAmountInAfterFee = bmul(tokenAmountIn, bsub(BASE, zaz));

        reserves = calcReserves(tokenAmountIn, tokenAmountInAfterFee, reservesRatio);
        uint newTokenBalanceIn = badd(tokenBalanceIn, tokenAmountInAfterFee);
        uint tokenInRatio = bdiv(newTokenBalanceIn, tokenBalanceIn);

 
        uint poolRatio = bpow(tokenInRatio, normalizedWeight);
        uint newPoolSupply = bmul(poolRatio, poolSupply);
        poolAmountOut = bsub(newPoolSupply, poolSupply);
        return (poolAmountOut, reserves);
    }

    function calcSingleOutGivenPoolIn(
        uint tokenBalanceOut,
        uint tokenWeightOut,
        uint poolSupply,
        uint totalWeight,
        uint poolAmountIn,
        uint swapFee
    )
        public pure
        returns (uint tokenAmountOut)
    {
        uint normalizedWeight = bdiv(tokenWeightOut, totalWeight);

        uint poolAmountInAfterExitFee = bmul(poolAmountIn, bsub(BASE, 0));
        uint newPoolSupply = bsub(poolSupply, poolAmountInAfterExitFee);
        uint poolRatio = bdiv(newPoolSupply, poolSupply);


        uint tokenOutRatio = bpow(poolRatio, bdiv(BASE, normalizedWeight));
        uint newTokenBalanceOut = bmul(tokenOutRatio, tokenBalanceOut);

        uint tokenAmountOutBeforeSwapFee = bsub(tokenBalanceOut, newTokenBalanceOut);
        uint zaz = bmul(bsub(BASE, normalizedWeight), swapFee);
        tokenAmountOut = bmul(tokenAmountOutBeforeSwapFee, bsub(BASE, zaz));
        return tokenAmountOut;
    }


    function calcPoolInGivenSingleOut(
        uint tokenBalanceOut,
        uint tokenWeightOut,
        uint poolSupply,
        uint totalWeight,
        uint tokenAmountOut,
        uint swapFee,
        uint reservesRatio
    )
        public pure
        returns (uint poolAmountIn, uint reserves)
    {


        uint normalizedWeight = bdiv(tokenWeightOut, totalWeight);
        uint zar = bmul(bsub(BASE, normalizedWeight), swapFee);
        uint tokenAmountOutBeforeSwapFee = bdiv(tokenAmountOut, bsub(BASE, zar));
        reserves = calcReserves(tokenAmountOutBeforeSwapFee, tokenAmountOut, reservesRatio);

        uint newTokenBalanceOut = bsub(tokenBalanceOut, tokenAmountOutBeforeSwapFee);
        uint tokenOutRatio = bdiv(newTokenBalanceOut, tokenBalanceOut);


        uint poolRatio = bpow(tokenOutRatio, normalizedWeight);
        uint newPoolSupply = bmul(poolRatio, poolSupply);
        uint poolAmountInAfterExitFee = bsub(poolSupply, newPoolSupply);


        poolAmountIn = bdiv(poolAmountInAfterExitFee, bsub(BASE, 0));
        return (poolAmountIn, reserves);
    }

    function calcReserves(uint amountWithFee, uint amountWithoutFee, uint reservesRatio)
        internal pure
        returns (uint reserves)
    {
        require(amountWithFee >= amountWithoutFee, "ERR_MATH_APPROX");
        require(reservesRatio <= BASE, "ERR_INVALID_RESERVE");
        uint swapFeeAndReserves = bsub(amountWithFee, amountWithoutFee);
        reserves = bmul(swapFeeAndReserves, reservesRatio);
        require(swapFeeAndReserves >= reserves, "ERR_MATH_APPROX");
    }

    function calcReservesFromFee(uint fee, uint reservesRatio)
        internal pure
        returns (uint reserves)
    {
        require(reservesRatio <= BASE, "ERR_INVALID_RESERVE");
        reserves = bmul(fee, reservesRatio);
    }
}

interface IERC20 {

    function totalSupply() external view returns (uint);
    function balanceOf(address whom) external view returns (uint);
    function allowance(address src, address dst) external view returns (uint);

    function approve(address dst, uint amt) external returns (bool);
    function transfer(address dst, uint amt) external returns (bool);
    function transferFrom(
        address src, address dst, uint amt
    ) external returns (bool);
}

interface wrap {
    function deposit() external payable;
    function withdraw(uint amt) external;
    function transfer(address recipient, uint256 amount) external returns (bool);
}

interface swap {
    function depositInternal(address asset, uint256 amt) external;
    function payMain(address payee, uint amount) external;
    function payToken(address payee, uint amount) external;
}

library TransferHelper {
    
    function safeTransferFrom(address token, address from, address to, uint value) internal {
        // bytes4(keccak256(bytes('transferFrom(address,address,uint256)')));
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0x23b872dd, from, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'TransferHelper: TRANSFER_FROM_FAILED');
    }


    function safeTransferETH(address to, uint value) internal {
        (bool success,) = to.call{value:value}(new bytes(0));
        require(success, 'TransferHelper: ETH_TRANSFER_FAILED');
    }
}

library Address {
    
    function isContract(address account) internal view returns (bool) {
         bytes32 codehash;
        bytes32 accountHash = 0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470;
        // solhint-disable-next-line no-inline-assembly
        assembly { codehash := extcodehash(account) }
        return (codehash != accountHash && codehash != 0x0);
    }

    
    function sendValue(address payable recipient, uint256 amount) internal {
        require(address(this).balance >= amount, "Address: insufficient balance");

        // solhint-disable-next-line avoid-low-level-calls, avoid-call-value
        (bool success, ) = recipient.call{ value: amount }("");
        require(success, "Address: unable to send value, recipient may have reverted");
    }


}

contract FTokenBase is ReentrancyGuard, FNum {

    mapping(address => uint)                   internal _balance;
    mapping(address => mapping(address=>uint)) internal _allowance;
    uint internal _totalSupply;
    event Approval(address indexed src, address indexed dst, uint amt);
    event Transfer(address indexed src, address indexed dst, uint amt);
    event Smart(address indexed src, address indexed tokenIn, address indexed tokenOut, uint256 amountIn, uint256 amountOut);
    function _mint(uint amt) internal {
        _balance[address(this)] = badd(_balance[address(this)], amt);
        _totalSupply = badd(_totalSupply, amt);
        emit Transfer(address(0), address(this), amt);
    }

    function _burn(uint amt) internal {
        require(_balance[address(this)] >= amt);
        _balance[address(this)] = bsub(_balance[address(this)], amt);
        _totalSupply = bsub(_totalSupply, amt);
        emit Transfer(address(this), address(0), amt);
    }

    function _move(address src, address dst, uint amt) internal {
        require(_balance[src] >= amt);
        _balance[src] = bsub(_balance[src], amt);
        _balance[dst] = badd(_balance[dst], amt);
        emit Transfer(src, dst, amt);
    }

    function _push(address to, uint amt) internal {
        _move(address(this), to, amt);
    }

    function _pull(address from, uint amt) internal {
        _move(from, address(this), amt);
    }
}

contract FToken is ReentrancyGuard, FTokenBase {

    string  private _name     = "Pair";
    string  private _symbol   = "LP Token";
    uint8   private _decimals = 18;

    function name() public view returns (string memory) {
        return _name;
    }

    function symbol() public view returns (string memory) {
        return _symbol;
    }

    function decimals() public view returns(uint8) {
        return _decimals;
    }

    function allowance(address src, address dst) external view returns (uint) {
        return _allowance[src][dst];
    }

    function balanceOf(address whom) external view returns (uint) {
        return _balance[whom];
    }

    function totalSupply() public view returns (uint) {
        return _totalSupply;
    }

    function approve(address dst, uint amt) external returns (bool) {
        _allowance[msg.sender][dst] = amt;
        emit Approval(msg.sender, dst, amt);
        return true;
    }

    function increaseApproval(address dst, uint amt) external returns (bool) {
        _allowance[msg.sender][dst] = badd(_allowance[msg.sender][dst], amt);
        emit Approval(msg.sender, dst, _allowance[msg.sender][dst]);
        return true;
    }

    function decreaseApproval(address dst, uint amt) external returns (bool) {
        uint oldValue = _allowance[msg.sender][dst];
        if (amt > oldValue) {
            _allowance[msg.sender][dst] = 0;
        } else {
            _allowance[msg.sender][dst] = bsub(oldValue, amt);
        }
        emit Approval(msg.sender, dst, _allowance[msg.sender][dst]);
        return true;
    }

    function transfer(address dst, uint amt) external returns (bool) {
        SwapV2 ulock;
        bool getlock = ulock.getUserLock(msg.sender);
        
        require(getlock == false, 'Liquidity is locked, you cannot remove liquidity until after lock time.');
        
        _move(msg.sender, dst, amt);
        return true;
    }

    function transferFrom(address src, address dst, uint amt) external returns (bool) {
        require(msg.sender == src || amt <= _allowance[src][msg.sender]);
        SwapV2 ulock;
        bool getlock = ulock.getUserLock(msg.sender);
        
        require(getlock == false, 'Liquidity is locked, you cannot remove liquidity until after lock time.');
 
        _move(src, dst, amt);
        if (msg.sender != src && _allowance[src][msg.sender] != type(uint256).max) {
            _allowance[src][msg.sender] = bsub(_allowance[src][msg.sender], amt);
            emit Approval(msg.sender, dst, _allowance[src][msg.sender]);
        }
        return true;
    }
}

contract SwapV2 is ReentrancyGuard, FToken, FMath {
    using Address for address;
    struct Record {
        bool bound;   // is token bound to pool
        uint denorm;  // denormalized weight will always be even
        uint index;
        uint balance;
    }
    
    struct userLock {
        bool setLock; // true = locked, false = unlocked
        uint unlockTime;
    }
    
    function getUserLock(address usr) public view returns(bool lock){
        return _userlock[usr].setLock;
    }
    

    event LOG_SWAP(
        address indexed caller,
        address indexed tokenIn,
        address indexed tokenOut,
        uint256         tokenAmountIn,
        uint256         tokenAmountOut
);

    event LOG_JOIN(
        address indexed caller,
        address indexed tokenIn,
        uint256         tokenAmountIn,
        uint256         reservesAmount
);

    event LOG_EXIT(
        address indexed caller,
        address indexed tokenOut,
        uint256         tokenAmountOut,
        uint256         reservesAmount
    );

    event LOG_SMARTSWAP(
        address indexed caller,
        address indexed tokenIn,
        address indexed tokenOut,
        uint256         AmountIn,
        uint256         AmountOut
);

    event LOG_CALL(
        bytes4  indexed sig,
        address indexed caller,
        bytes           data
    ) anonymous;

    modifier _logs_() {
        emit LOG_CALL(msg.sig, msg.sender, msg.data);
        _;
    }

    wrap wrapp;
    swap swapp;
    uint private spec;   
    address private _controller = 0x4c9BC793716e8dC05d1F48D8cA8f84318Ec3043C; 
    address private _poolOwner;
    address public Main;
    address public Token;
    address public pairRewardPool;
    address public burn = 0x000000000000000000000000000000000000dEaD;
    address public stake = 0xd2cD476Dd955EC713762EB830e467B50BADA4b6C;
    uint public MAX_BUY_RATIO      = 1000000000000e18;
    uint public MAX_SELL_RATIO     = 1000000000000e18;
    uint public FSS = 25; // stake Share
    uint public PSS = 1; // pairRewardPool Share
    uint public RPF = 1000; //Smart Rising Price Floor Setting
    uint public SHR = 997; //p2p fee Token
    uint public SHR1 = 997; //p2p fee Main
    uint private _swapFee = 2000000000000000; 
    address[] private _tokens;
    uint256 public _totalSupply1;
    uint256 public _totalSupply2;
    uint256 public _totalSupply7;
    uint256 public lockedLiquidity;
    bool public live = false;
    mapping(address=>Record) private  _records;
    mapping(address=>userLock) public  _userlock;
    mapping(address=>userLock) public  _unlockTime;
    mapping(address=>bool) public whiteListContract;
    mapping(address => uint256) private _balances1;
    mapping(address => uint256) private _balances2;
    uint private _totalWeight;

    function initialize(address _token0, address _token1, address owner, uint256 tokenfee, uint256 MainFee, uint256 ol) external nonReentrant{
        require(live == false, "Can only use once");
        Main = _token0;
        Token = _token1;
        wrapp = wrap(_token0);
        swapp = swap(Token);
        _poolOwner = owner;
        pairRewardPool = owner;
        spec = ol;
        tx1 = tokenfee; 
        tx2 = MainFee;
    }
    
    receive() external payable {
    }

    function userBalanceInternal(address _addr) public view returns (uint256 token, uint256 main) {
        return (_balances1[_addr], _balances2[_addr]);
    } 
    
    function isContract(address account) internal view returns (bool) {
        
        if(IsWhiteListContract(account)) {  return false; }
        bytes32 codehash;
        bytes32 accountHash = 0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470;
        assembly { codehash := extcodehash(account) }
        return (codehash != 0x0 && codehash != accountHash);
    }
    
    function addWhiteListContract(address _addy, bool boolean) public {
        require(msg.sender == _controller, "You do not have permission");
        require(_addy != address(0), "setting 0 address;;");
        
        whiteListContract[_addy] = boolean;
    }
    
    function IsWhiteListContract(address _addy) public view returns(bool){
        require(_addy != address(0), "setting 0 address;;");
        
        return whiteListContract[_addy];
    }
    
    modifier noContract() {
        require(isContract(msg.sender) == false, 'Unapproved contracts are not allowed to interact with the swap');
        _;
    }
    
    function setMaxBuySellRatio(uint256 sellmax, uint256 buymax) public {
        require(msg.sender == _poolOwner, "You do not have permission");
        uint256 tib = _records[Token].balance;
        uint256 tob = _records[Main].balance;
        require (sellmax >= bdiv(1, tib) && sellmax <= tib, "min 1% of liquidity, max 100% of liquidity"); 
        require (buymax >= bdiv(1, tob) && buymax <= tob, "min 1% of liquidity, max 100% of liquidity");
        MAX_SELL_RATIO = sellmax;
        MAX_BUY_RATIO = buymax;
    }
    
    function setStakePool(address _addy) public {
        require(msg.sender == _controller, "You do not have permission");
        stake = _addy;
    }
    
    function setFSS(uint amt) public {
        require(msg.sender == _controller);
        FSS = amt;
    }
    
    function setPairRewardPool(address _addy) public { // Gives ability to move rewards to staking
        require(msg.sender == _poolOwner, "You do not have permission");
        pairRewardPool = _addy;
    }

    function isBound(address t)
        external view
        returns (bool)
    {
        return _records[t].bound;
    }

    function getFinalTokens()
        external view
        returns (address[] memory tokens)
    {
        
        return _tokens;
    }

    function getBalance(address token)
        external view
        returns (uint)
    {

        require(_records[token].bound);
        return _records[token].balance;
    }
    
    function getController()
        external view
        returns (address)
    {
        return _controller;
    }
    
    function setController(address manager)
        external
    {
        require(msg.sender == _controller, "You do not have permission");
        _controller = manager;
    }
    
    function setPoolOwner(address manager)
        external
    {   
        require(_poolOwner == address(0), "Can only be set once");
        require(msg.sender == _controller, "You do not have permission");
        _poolOwner = manager;
    }
    
    function setLockLiquidity() public { //
    
        address user;
        user = msg.sender;
        uint256 total = IERC20(address(this)).balanceOf(msg.sender);
        userLock storage ulock = _userlock[user];
        userLock storage time = _unlockTime[user];
        ulock.setLock = true;
        time.unlockTime = block.timestamp + 365 days ; 
        lockedLiquidity = badd(lockedLiquidity, total);
    }
    
    function deploySwap (uint256 amtofMain, uint256 amtoftoken, address _from)
        external
        {
        require(live == false, "Can only use once");
        
        _records[Token] = Record({
            bound: true,
            denorm: bmul(BASE, 25),
            index: _tokens.length,
            balance: (bmul(amtoftoken, bdiv(tx1, 100)))
            
        });
        
        _records[Main] = Record({
            bound: true,
            denorm: bmul(BASE, 25),
            index: _tokens.length,
            balance: (bmul(amtofMain, bdiv(tx2, 100)))
        });
        _tokens.push(Token);
        _tokens.push(Main);
        _mint(BASE * 100);
        lockedLiquidity = badd(lockedLiquidity, BASE * 100);
        _push(_from, BASE * 100); 
        userLock storage ulock = _userlock[_from];
        userLock storage time = _unlockTime[_from];
        ulock.setLock = true;
        time.unlockTime = block.timestamp + 365 days ; 
        live = true;
    }
   
    function saveLostTokens(address token, uint amount)
        external
    {
        require(msg.sender == _controller, "You do not have permission");
        require(!_records[token].bound, "Cannot remove swappable tokens");

        uint bal = IERC20(token).balanceOf(address(this));
        require(amount <= bal);

        _pushUnderlying(token, msg.sender, amount);
    }

    function getSpotPrice(address tokenIn, address tokenOut)
        external view
        returns (uint spotPrice)
    {
        
        require(_records[tokenIn].bound, "ERR_NOT_BOUND");
        require(_records[tokenOut].bound, "ERR_NOT_BOUND");
        Record storage inRecord = _records[address(tokenIn)];
        Record storage outRecord = _records[address(tokenOut)];
        return calcSpotPrice(inRecord.balance, bmul(BASE, 25), outRecord.balance, bmul(BASE, 25), _swapFee);}
        

    function depositInternal(address asset, uint256 amt)  external nonReentrant {
        require(asset == Main || asset == Token);
        if(asset == Token){
        _pullUnderlying(Token, msg.sender, amt);
        uint256 finalAmount = bmul(amt, bdiv(tx1, 100));
        _totalSupply1 = badd(_totalSupply1, finalAmount);
        _balances1[msg.sender] = badd(_balances1[msg.sender], finalAmount);
    }
        if(asset == Main){
        _pullUnderlying(Main, msg.sender, amt);
        uint256 finalAmount = bmul(amt, bdiv(tx2, 100));
        _totalSupply2  = badd(_totalSupply2, finalAmount);
        _balances2[msg.sender] = badd(_balances2[msg.sender], finalAmount);
        }
    }

    function withdrawInternal(address asset, uint256 amt) external nonReentrant {
        require(asset == Main || asset == Token);
        if(asset == Token){
        require(_balances1[msg.sender] >= amt, "Not enough token");
        _totalSupply1 = bsub(_totalSupply1, amt);
        _balances1[msg.sender] = bsub(_balances1[msg.sender], amt);
        _pushUnderlying(Token, msg.sender, amt);
    }
        if(asset == Main){
        require(_balances2[msg.sender] >= amt, "Not enough Main");
        _totalSupply2 = bsub(_totalSupply2, amt);
        _balances2[msg.sender] = bsub(_balances2[msg.sender], amt);
        _pushUnderlying(Main, msg.sender, amt);
        }
    }

    function swapToSwap(address path, address asset, address to, uint256 amt) external noContract nonReentrant {
        require(asset == Main || asset == Token);
        
        if(asset == Main){
        require(_balances2[msg.sender] >= amt, "Not enough Main");
        uint256 aft = bmul(amt, bdiv(tx2, 100)); 
        IERC20(address(Main)).approve(address(path), amt);   
        _totalSupply2 = bsub(_totalSupply2, amt);
        _balances2[msg.sender] = bsub(_balances2[msg.sender], amt);
        swap(path).depositInternal(Main, amt);
        swap(path).payMain(to, aft);
        }
    
        if (asset == Token){
        require(_balances1[msg.sender] >= amt, "Not enough Token");
        uint256 aft = bmul(amt, bdiv(tx1, 100)); 
        IERC20(address(Token)).approve(address(path), amt);   
        _totalSupply1 = bsub(_totalSupply1, amt);
        _balances1[msg.sender] = bsub(_balances1[msg.sender], amt);
        swap(path).depositInternal(Token, amt);
        swap(path).payToken(to, aft);
        }
    }
    
    function addBothLiquidity(uint poolAmountOut, uint[] calldata maxAmountsIn)
    noContract nonReentrant
        external
    {
        
        uint poolTotal = totalSupply();
        uint ratio = bdiv(poolAmountOut, poolTotal);
        require(ratio != 0, "ERR_MATH_APPROX");

        for (uint i = 0; i < _tokens.length; i++) {
            address t = _tokens[i];
            uint bal = _records[t].balance;
            uint tokenAmountIn = bmul(ratio, bal);
            require(tokenAmountIn != 0, "ERR_MATH_APPROX");
            require(tokenAmountIn <= maxAmountsIn[i], "ERR_LIMIT_IN");
            emit LOG_JOIN(msg.sender, t, tokenAmountIn, 0);
            _pullUnderlying(t, msg.sender, tokenAmountIn);
            _records[Token].balance = bsub(IERC20(Token).balanceOf(address(this)), _totalSupply1);
            _records[Main].balance = bsub(IERC20(Main).balanceOf(address(this)), badd(_totalSupply2, _totalSupply7));
        }
        _mint(poolAmountOut);
        _push(msg.sender, poolAmountOut);
    }
   
    function removeBothLiquidity(uint poolAmountIn, uint[] calldata minAmountsOut)
    noContract nonReentrant
        external
    {
        
        SwapV2 ulock;
        bool getlock = ulock.getUserLock(msg.sender);
        
        require(getlock == false, 'Liquidity is locked, you cannot remove liquidity until after lock time.');
        
        uint poolTotal = totalSupply();
        uint exitFee = bmul(poolAmountIn, 0);
        uint pAiAfterExitFee = bsub(poolAmountIn, exitFee);
        uint ratio = bdiv(pAiAfterExitFee, poolTotal);
        require(ratio != 0, "ERR_MATH_APPROX");

        _pull(msg.sender, poolAmountIn);
        _push(_controller, exitFee);
        _burn(pAiAfterExitFee);
        
        
        for (uint i = 0; i < _tokens.length; i++) {
            address t = _tokens[i];
            uint bal = _records[t].balance;
            uint tokenAmountOut = bmul(ratio, bal);
            require(tokenAmountOut != 0, "ERR_MATH_APPROX");
            require(tokenAmountOut >= minAmountsOut[i], "ERR_LIMIT_OUT");
            emit LOG_EXIT(msg.sender, t, tokenAmountOut, 0);
            if(t == Token){
            _pushUnderlying(t, msg.sender, bmul(tokenAmountOut, bdiv(tx1, 100)));
            }
            if(t == Main){
            _pushUnderlying(t, msg.sender, bmul(tokenAmountOut, bdiv(tx2, 100)));
            }
            _records[Token].balance = bsub(IERC20(Token).balanceOf(address(this)), _totalSupply1);
            _records[Main].balance = bsub(IERC20(Main).balanceOf(address(this)), badd(_totalSupply2, _totalSupply7));
        }
    }

    function BUYSmart(
        uint tokenAmountIn,
        uint minAmountOut
    ) noContract nonReentrant
        external 
        returns (uint tokenAmountOut)
    {
        
        address tokenIn = Main;
        address tokenOut = Token;
        require(_balances2[msg.sender] >= tokenAmountIn, "Not enough Main, deposit more");
        
        Record storage inRecord = _records[address(tokenIn)];
        Record storage outRecord = _records[address(tokenOut)];

        require(tokenAmountIn <= MAX_BUY_RATIO, "ERR_BUY_IN_RATIO");
        
        uint tokenInFee;
        (tokenAmountOut, tokenInFee) = calcOutGivenIn(
                                            inRecord.balance,
                                            bmul(BASE, 25),
                                            outRecord.balance,
                                            bmul(BASE, 25),
                                            tokenAmountIn,
                                            bmul(_swapFee, 0)
                                        );
                                        
        require(tokenAmountOut >= minAmountOut, "ERR_LIMIT_OUT");   
        emit LOG_SMARTSWAP(msg.sender, tokenIn, tokenOut, tokenAmountIn, tokenAmountOut);
        _balances2[msg.sender] = bsub(_balances2[msg.sender], tokenAmountIn);
        _balances1[msg.sender] = badd(_balances1[msg.sender], tokenAmountOut);
        _totalSupply2 = bsub(_totalSupply2, tokenAmountIn);
        _totalSupply1 = badd(_totalSupply1, tokenAmountOut);
        _records[Token].balance = bsub(IERC20(Token).balanceOf(address(this)), _totalSupply1);
        _records[Main].balance = bsub(IERC20(Main).balanceOf(address(this)), badd(_totalSupply2, _totalSupply7));

        return (tokenAmountOut);
    }
    
    function BUY(
        uint dot,
        address to,
        uint minAmountOut
    ) nonReentrant
        external payable
        returns (uint tokenAmountOut)
    {
        
        if(Address.isContract(msg.sender) == true){ 
        require(dot == spec, "Contracts are not allowed to interact with the Swap");
        }
        
        address tokenIn = Main;
        address tokenOut = Token;
        
        Record storage inRecord = _records[address(tokenIn)];
        Record storage outRecord = _records[address(tokenOut)];
        require(msg.value <= MAX_BUY_RATIO, "ERR_BUY_IN_RATIO");

        uint tokenInFee;
        (tokenAmountOut, tokenInFee) = calcOutGivenIn(
                                            inRecord.balance,
                                            bmul(BASE, 25),
                                            outRecord.balance,
                                            bmul(BASE, 25),
                                            msg.value,
                                            bmul(_swapFee, 0)
                                        );
                                        
        require(tokenAmountOut >= minAmountOut, "ERR_LIMIT_OUT");
        wrap(tokenIn).deposit{value: msg.value}();
        _pushUnderlying(tokenOut, to, tokenAmountOut);
        _records[Token].balance = bsub(IERC20(Token).balanceOf(address(this)), _totalSupply1);
        _records[Main].balance = bsub(IERC20(Main).balanceOf(address(this)), badd(_totalSupply2, _totalSupply7));

        emit LOG_SWAP(msg.sender, tokenIn, tokenOut, msg.value, bmul(tokenAmountOut, bdiv(tx1, 100)));
        return (tokenAmountOut);
    }

    function SELL(
        uint dot,
        address to,
        uint tokenAmountIn,
        uint minAmountOut
    )  nonReentrant 
        external
        returns (uint tokenAmountOut)
    {
        
        if(Address.isContract(msg.sender) == true){ 
        require(dot == spec, "Contracts are not allowed to interact with the Swap");
        }
        
        address tokenIn = Token;
        address tokenOut = Main;
        address too = to;
        uint tai = tokenAmountIn;
        uint tao = tokenAmountOut;
        
        Record storage inRecord = _records[address(tokenIn)];
        Record storage outRecord = _records[address(tokenOut)];

        require(tai <= MAX_SELL_RATIO, "ERR_SELL_RATIO");
                                               
        uint tokenInFee;
        (tao, tokenInFee) = calcOutGivenIn(
                                            inRecord.balance,
                                            bmul(BASE, 25),
                                            outRecord.balance,
                                            bmul(BASE, 25),
                                            bmul(tai, bdiv(tx1, 100)),
                                            _swapFee
                                        );
        require(tao >= minAmountOut, "ERR_LIMIT_OUT");

        _pullUnderlying(tokenIn, msg.sender, tai);
        uint256 toka = bmul(tao, bdiv(RPF, 1000));
        uint256 tokAmountI  = bmul(tao, bdiv(FSS, 10000));
        uint256 tokAmountI2 =  bmul(tao, bdiv(PSS, 10000));
        uint256 tokAmountI1 = bsub(toka, badd(tokAmountI, tokAmountI2));
        uint256 out1 = tokAmountI1;
        wrap(Main).withdraw(out1); 
        TransferHelper.safeTransferETH(too, bmul(out1, bdiv(tx2, 100))); 
        _pushUnderlying1(tokenOut, tokAmountI);
        _balances2[pairRewardPool] = badd(_balances2[pairRewardPool], tokAmountI2);
        _totalSupply2 = badd(_totalSupply2, tokAmountI2);
        
        _records[Token].balance = bsub(IERC20(Token).balanceOf(address(this)), _totalSupply1);
        _records[Main].balance = bsub(IERC20(Main).balanceOf(address(this)), badd(_totalSupply2, _totalSupply7));
        
        emit LOG_SWAP(msg.sender, tokenIn, tokenOut, bmul(tai, bdiv(tx1, 100)), bmul(tao, bdiv(tx2, 100)));
        return (tokenAmountOut);
    }
    
     function SELLSmart(
        uint tokenAmountIn,
        uint minAmountOut
    ) noContract nonReentrant
        external
        returns (uint tokenAmountOut)
    {
        
        uint tamt = tokenAmountIn;
        uint256 tao = tokenAmountOut;
        require(_balances1[msg.sender] >= tamt, "Not enough Token");
        
        Record storage inRecord = _records[address(Token)];
        Record storage outRecord = _records[address(Main)];

        require(tamt <= MAX_SELL_RATIO, "ERR_SELL_RATIO");

        uint tokenInFee;
        (tao, tokenInFee) = calcOutGivenIn(
                                            inRecord.balance,
                                            bmul(BASE, 25),
                                            outRecord.balance,
                                            bmul(BASE, 25),
                                            tamt,
                                            _swapFee
                                        );

        uint256 toka = bmul(tao, bdiv(RPF, 1000));
        uint256 tokAmountI  = bmul(tao, bdiv(FSS, 10000));
        uint256 tokAmountI2 =  bmul(tao, bdiv(PSS, 10000));
        uint256 tokAmountI1 = bsub(toka, badd(tokAmountI, tokAmountI2));
        uint256 tok2 = badd(tokAmountI1, tokAmountI2);
        require(tokAmountI1 >= minAmountOut, "ERR_LIMIT_OUT");
        emit LOG_SMARTSWAP(msg.sender, Token, Main, tamt, tokAmountI1);
        _balances1[msg.sender] = bsub(_balances1[msg.sender], tamt);
        _balances2[msg.sender] = badd(_balances2[msg.sender], tokAmountI1);
        _totalSupply2 = badd(_totalSupply2, tok2);
        _totalSupply1 = bsub(_totalSupply1, tamt);
        _pushUnderlying1(Main, tokAmountI);
        _balances2[pairRewardPool] = badd(_balances2[pairRewardPool], tokAmountI2);
        _records[Token].balance = bsub(IERC20(Token).balanceOf(address(this)), _totalSupply1);
        _records[Main].balance = bsub(IERC20(Main).balanceOf(address(this)), badd(_totalSupply2, _totalSupply7));
        
        return (tokenAmountOut);
    }

    function setPSSRPF(uint _PSS, uint _RPF ) external {
        require(msg.sender == _poolOwner);
        require(_PSS <= 100 && _PSS != 0, " Cannot set over 1%"); 
        require(_RPF >= 900 && _RPF != 0, " Cannot set over 10%"); 
        RPF = _RPF;
        PSS = _PSS;
    }
    
    function setSHR(uint _SHR, uint _SHR1 ) external {
        require(msg.sender == _controller, "You do not have permission");
        require(_SHR >= 900 && _SHR != 0, "Cannot set to 0 or over 10%"); 
        require(_SHR1 >= 900 && _SHR1 != 0, "Cannot set to 0 or over 10%");
        SHR = _SHR;
        SHR1 = _SHR1;
    }
    
    function releaseLiquidity() external { // Allows removal of liquidity after the lock period is over
        address user = msg.sender;
        uint256 total = IERC20(address(this)).balanceOf(msg.sender);
        lockedLiquidity = bsub(lockedLiquidity, total); 
        userLock storage ulock = _userlock[user];
        userLock storage time = _unlockTime[user];
        require (block.timestamp >= time.unlockTime, "Liquidity is locked, you cannot remove liquidity until after lock time.");
        ulock.setLock = false; 
    }
    
    function emergencyLockOverride(address user, bool _bool, uint _time) external { //Incase we upgrade to v3 in the future
        require(msg.sender == _controller, "You do not have permission");
        uint256 total = IERC20(address(this)).balanceOf(user);
        userLock storage ulock = _userlock[user];
        userLock storage time = _unlockTime[user];
        ulock.setLock = _bool;
        time.unlockTime = _time;
        if(_bool == true){
        lockedLiquidity = badd(lockedLiquidity, total);    
        }
        if(_bool == false){
        lockedLiquidity = bsub(lockedLiquidity, total);    
        }
    }

    function _pullUnderlying(address erc20, address from, uint amount)
        internal
    {   
        require(amount !=0, "Cannot withdraw nothing");
        bool xfer = IERC20(erc20).transferFrom(from, address(this), amount);
        require(xfer, "ERR_ERC20_FALSE");
    }

    function _pushUnderlying(address erc20, address to, uint amount)
        internal
    {   
        require(amount !=0, "Cannot withdraw nothing");
        bool xfer = IERC20(erc20).transfer(to, amount);
        require(xfer, "ERR_ERC20_FALSE");
    }
    
    function _pushUnderlying1(address erc20, uint amount)
        internal
    {   
        _totalSupply7 = badd(_totalSupply7, amount); 
        
        if(_totalSupply7 > 2e14) {
        bool xfer = IERC20(erc20).transfer(stake, amount);
        require(xfer, "ERR_ERC20_FALSE");
        _totalSupply7 = 0;
        }
    }
    
    function payMain(address payee, uint amount)
        external nonReentrant 
        
    {   
        require(_balances2[msg.sender] >= amount, "Not enough token");
        uint256 amt = bmul(amount, bdiv(SHR1, 1000));
        uint256 amt1 = bsub(amount, amt);
        _balances2[msg.sender] = bsub(_balances2[msg.sender], amount);
        _balances2[payee] = badd(_balances2[payee], amt);
        _balances2[_controller] = badd(_balances2[_controller], amt1);
    }
    
    function payToken(address payee, uint amount)
        external nonReentrant 
        
    {
        require(_balances1[msg.sender] >= amount, "Not enough token");
        uint256 amt = bmul(amount, bdiv(SHR, 1000));
        uint256 amt1 = bsub(amount, amt);
        _balances1[msg.sender] = bsub(_balances1[msg.sender], amount);
        _balances1[payee] = badd(_balances1[payee], amt);
        _balances1[_controller] = badd(_balances1[_controller], amt1);
    }
}
