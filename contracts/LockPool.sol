// SPDX-License-Identifier: MIT

pragma solidity ^0.6.6;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/math/SafeMath.sol";
import '@openzeppelin/contracts/access/Ownable.sol';
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/introspection/ERC165.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721Holder.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/EnumerableSet.sol";
import "./IGofNft.sol";

contract LockPool is Ownable, Pausable, ERC721Holder, ERC165{
    using EnumerableSet for EnumerableSet.UintSet;
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    struct Order {
        uint id;
        address user;
        uint amount;
        uint period;
        uint weight;
        uint unlockTime;
        bool unlock;
    }

    struct UserInfo {
        uint balance; 
        uint lockBalance;
        uint weightBalance;
        uint weightSupply;
        uint rewardDebt;
        uint rewardPending;
        uint rewardTotal;
        mapping(uint => uint[])  ids;
    }

    address public gof;
    uint[] public periods ;
    uint[] public weights;
    uint[] public intervals ;
 
    uint public totalSupply;
    uint public weightTotalSupply;
    uint public rewardRate;
    uint public rewardPerTokenStored; // = rewardRate * locktime / weightTotalSupply
    uint public lastUpdateTime;
    uint public id;
    address[] public nfts;

    mapping(address => bool) public supportsNft;
    mapping(uint => Order) public orders;
    mapping(address => UserInfo) public userInfo;
    mapping(address => mapping(uint => uint)) public lastLocTime;
    mapping(address => mapping(address => EnumerableSet.UintSet)) userTokenIds;

    event Lock(address indexed user, uint256 indexed period, uint256 amount, uint256 id, uint256 unlockTime, uint256 lockTime, uint256 weight);
    event Unlock(address indexed user, uint256 indexed period, uint256 amount, uint256 id);
    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 amount);
    event SetRewardRate(uint256 oldRewardRate, uint256 newRewardRate);
    event DepositNFT(address indexed user, address indexed nft, uint256 indexed tokenId);
    event WithdrawNFT(address indexed user, address indexed nft, uint256 indexed tokenId);

    constructor(address _gof, uint _rewardRate, uint[] memory _periods, uint[] memory _intervals, uint[] memory _weights) public {
        gof = _gof;
        rewardRate = _rewardRate;
        lastUpdateTime = block.timestamp;
        periods = _periods;
        intervals = _intervals;
        weights = _weights;
        _registerInterface(IERC721Receiver.onERC721Received.selector);
    }

    modifier checkPeriod(uint _period) {
        require(_period < periods.length, "Unsupport period");
        _;
    }

    function apr(uint _period) external view returns(uint) {
        if (weightTotalSupply == 0) {
            return 0;
        }
        return rewardRate.mul(31536000).mul(weights[_period]).div(weightTotalSupply);
    }

    function orderLength(address _user, uint _period) external view returns(uint) {
        return userInfo[_user].ids[_period].length;
    }

    function orderIds(address _user, uint _period) external view returns(uint[] memory) {
        return userInfo[_user].ids[_period];
    }

    function userOrders(address _user, uint _period) external view returns(Order[] memory){
        return userOrdersPage(_user, _period, 0, userInfo[_user].ids[_period].length);
    }

    function userOrdersPage(address _user, uint _period, uint _page, uint _size) public view returns(Order[] memory){
        uint[] memory idArr = userInfo[_user].ids[_period];
        uint256 _start = _page < 2 ? 0 : _page.sub(1).mul(_size);
        uint limit = _start.add(_size);
        if (limit > idArr.length) {
            limit = idArr.length;
        }

        if (limit <= _start) {
            return new Order[](0);
        }

        Order[] memory _orderList = new Order[](limit.sub(_start));
        for (uint len = 0 ; _start < limit; _start++) {
            _orderList[len] = orders[idArr[_start]]; 
            len++;
        }

        return _orderList;            
    }

    function weightBalance(address _user) external view returns(uint) {
        return userInfo[_user].weightBalance;
    }

    function weightSupply(address _user) external view returns(uint) {
        return userInfo[_user].weightSupply;
    }

    function lockBalance(address _user) external view returns(uint) {
        return userInfo[_user].lockBalance;
    }

    function balance(address _user) external view returns(uint) {
        return userInfo[_user].balance;
    }

    function tokenIdLength(address _user, address _nft) external view returns(uint) {
        return userTokenIds[_user][_nft].length();
    }

    function tokenId(address _user, address _nft) external view returns(uint256[] memory) {
        EnumerableSet.UintSet storage tokenIds = userTokenIds[_user][_nft];
        uint256 len = tokenIds.length();
        uint256[] memory _ids = new uint256[](len);
        for (uint256 i = 0; i < len; i++) {
            _ids[i] = tokenIds.at(i);  
        }
        return _ids;
    }

    function setRewardRate(uint _rewardRate) external onlyOwner {
        updatePool();
        emit SetRewardRate(rewardRate, _rewardRate);
        rewardRate = _rewardRate;
    }

    function pendingReward(address _user) external view returns(uint) {
        uint rewardPerToken = rewardPerTokenStored;
        if (block.timestamp > lastUpdateTime && weightTotalSupply != 0) {
            uint rewardAdd = rewardRate.mul(block.timestamp.sub(lastUpdateTime));
            rewardPerToken = rewardPerToken.add(rewardAdd.mul(1e18).div(weightTotalSupply));
        }

        UserInfo memory user = userInfo[_user];

        uint pending = user.rewardPending;
        if (user.weightSupply > 0) {
            pending = pending.add(user.weightSupply.mul(rewardPerToken).div(1e18).sub(user.rewardDebt));
        }
        return pending;
    }

    function updatePool() public {
        if (block.timestamp <= lastUpdateTime) {
            return;
        }

        if (weightTotalSupply == 0) {
            lastUpdateTime = block.timestamp;
            return;
        }

        uint rewardAdd = rewardRate.mul(block.timestamp.sub(lastUpdateTime));
        rewardPerTokenStored = rewardPerTokenStored.add(rewardAdd.mul(1e18).div(weightTotalSupply));
        lastUpdateTime = block.timestamp;
    }

    function nftWeightAmount(uint _amount, address _user) internal view returns(uint) {
        for (uint256 index = 0; index < nfts.length; index++) {
            EnumerableSet.UintSet storage tokenIds = userTokenIds[_user][nfts[index]];
            uint256 len = tokenIds.length();
            for (uint256 i = 0; i < len; i++) {
                _amount = _amount.mul(IGofNft(nfts[index]).getBoardFactor(tokenIds.at(i))).div(1e18);   
            }
        }
        return _amount;
    }

    function lock(uint _amount, uint _period) external whenNotPaused checkPeriod(_period) {
        if (_period == 0) {
            deposit(_amount);
            return;
        }

        require(_amount > 0, "Lock 0");
        uint llt = lastLocTime[msg.sender][_period];
        require(llt == 0 || block.timestamp >= llt.add(intervals[_period]), "Operation is too frequent");

        updatePool();

         _getReward(false);

        IERC20(gof).safeTransferFrom(msg.sender, address(this), _amount);
        UserInfo storage user = userInfo[msg.sender];
        totalSupply = totalSupply.add(_amount);
        user.lockBalance = user.lockBalance.add(_amount);

        uint weightAmount = _amount.mul(weights[_period]).div(1e18);
        user.weightBalance = user.weightBalance.add(weightAmount);

        uint supplyAmount = nftWeightAmount(user.weightBalance, msg.sender);
        weightTotalSupply = weightTotalSupply.add(supplyAmount).sub(user.weightSupply);
        user.weightSupply = supplyAmount;
        // save order
        Order memory order = Order({
            id: id,
            user: msg.sender,
            amount: _amount,
            period: _period,
            weight: weights[_period],
            unlockTime: (_period == 0 ? 0 : block.timestamp.add(periods[_period])),
            unlock: false
        });

        orders[id] = order;
        user.rewardDebt = user.weightSupply.mul(rewardPerTokenStored).div(1e18);
        user.ids[_period].push(id);
        lastLocTime[msg.sender][_period] = block.timestamp;

        emit Lock(msg.sender, _period, _amount, id, order.unlockTime, block.timestamp, weights[_period]);

        id = id.add(1);
    }

    function unlockMulti(uint[] calldata _ids) external {
        for (uint256 index = 0; index < _ids.length; index++) {
             _unlock(_ids[index], false);
        }
    }

    function unlock(uint _id) external {
        _unlock(_id, true);
    }

    function _unlock(uint _id, bool _f) internal {
        Order memory order = orders[_id];
        if (order.user == address(0)) {
            require(!_f, "Order is unfound");
            return;
        }
        if (order.unlock) {
            require(!_f, "Order is unlocked");
            return;
        }
        if (block.timestamp < order.unlockTime) {
            require(!_f, "Invalid operate");
            return;
        }

        updatePool();

        UserInfo storage user = userInfo[order.user];
        if (user.weightSupply > 0) {
            uint pending = user.weightSupply.mul(rewardPerTokenStored).div(1e18).sub(user.rewardDebt);
            user.rewardPending = user.rewardPending.add(pending);
        }

        user.lockBalance = user.lockBalance.sub(order.amount);
        user.balance = user.balance.add(order.amount);

        uint weightAmount = order.amount.mul(order.weight).div(1e18);
        user.weightBalance = user.weightBalance.add(order.amount).sub(weightAmount);

        uint supplyAmount = nftWeightAmount(user.weightBalance, order.user);
        weightTotalSupply = weightTotalSupply.add(supplyAmount).sub(user.weightSupply);
        user.weightSupply = supplyAmount;

        user.rewardDebt = user.weightSupply.mul(rewardPerTokenStored).div(1e18);
        orders[_id].unlock = true;

        emit Unlock(order.user, order.period, order.amount, _id);
    }

    function deposit(uint _amount) public whenNotPaused {
        updatePool();

         _getReward(false);

        UserInfo storage user = userInfo[msg.sender];
        if (_amount > 0) {
            IERC20(gof).safeTransferFrom(msg.sender, address(this), _amount);
            totalSupply = totalSupply.add(_amount);
            user.balance = user.balance.add(_amount);
            user.weightBalance = user.weightBalance.add(_amount);

            uint supplyAmount = nftWeightAmount(user.weightBalance, msg.sender);
            weightTotalSupply = weightTotalSupply.add(supplyAmount).sub(user.weightSupply);
            user.weightSupply = supplyAmount;
        }

        user.rewardDebt = user.weightSupply.mul(rewardPerTokenStored).div(1e18);

        emit Deposit(msg.sender, _amount);
    }

    function withdraw(uint _amount) external {
        updatePool();

        _getReward(false);

        UserInfo storage user = userInfo[msg.sender];
        if (_amount > user.balance) {
            _amount = user.balance;
        }

        if (_amount > 0) {
            totalSupply = totalSupply.sub(_amount);
            user.balance = user.balance.sub(_amount);
            user.weightBalance = user.weightBalance.sub(_amount);

            uint supplyAmount = nftWeightAmount(user.weightBalance, msg.sender);
            weightTotalSupply = weightTotalSupply.add(supplyAmount).sub(user.weightSupply);
            user.weightSupply = supplyAmount;
            IERC20(gof).safeTransfer(msg.sender, _amount);
        }
        user.rewardDebt = user.weightSupply.mul(rewardPerTokenStored).div(1e18);

        emit Withdraw(msg.sender, _amount);
    }

    function _getReward(bool _f) internal returns(uint){
        UserInfo storage user = userInfo[msg.sender];

        uint pending = user.rewardPending;
        if (user.weightSupply > 0) {
            pending = pending.add(user.weightSupply.mul(rewardPerTokenStored).div(1e18).sub(user.rewardDebt));
        }

        if (pending > 0) {
            uint rewardBalance = IERC20(gof).balanceOf(address(this)).sub(totalSupply);
            if (pending > rewardBalance) {
                require(!_f, "Insufficient reward");
                user.rewardPending = pending.sub(rewardBalance);
                pending = rewardBalance;
            } else {
                user.rewardPending = 0;
            }

            user.rewardTotal = user.rewardTotal.add(pending);
            IERC20(gof).safeTransfer(msg.sender, pending);
            emit RewardPaid(msg.sender, pending);
        }
    }

    function getReward() external {
        updatePool();

        _getReward(true);

        UserInfo storage user = userInfo[msg.sender];
        user.rewardDebt = user.weightSupply.mul(rewardPerTokenStored).div(1e18);
    }

    function depositNFT(address _nft, uint256 _tokenId) external whenNotPaused {
        require(supportsNft[_nft], "Unsupport!");
        EnumerableSet.UintSet storage tokenIds = userTokenIds[msg.sender][_nft];
        require(!tokenIds.contains(_tokenId), "Deposited!");

        updatePool();

        _getReward(false);

        IERC721(_nft).safeTransferFrom(msg.sender, address(this), _tokenId);
        tokenIds.add(_tokenId);

        UserInfo storage user = userInfo[msg.sender];
        if (user.weightBalance > 0) {
            uint supplyAmount = nftWeightAmount(user.weightBalance, msg.sender);
            weightTotalSupply = weightTotalSupply.add(supplyAmount).sub(user.weightSupply);
            user.weightSupply = supplyAmount;
        }

        user.rewardDebt = user.weightSupply.mul(rewardPerTokenStored).div(1e18);
        emit DepositNFT(msg.sender, _nft, _tokenId);
    }

    function withdrawNFT(address _nft, uint256 _tokenId) external {
        EnumerableSet.UintSet storage tokenIds = userTokenIds[msg.sender][_nft];
        require(tokenIds.contains(_tokenId), "TokenId is not found");

        updatePool();

        _getReward(false);

        IERC721(_nft).transferFrom(address(this), msg.sender, _tokenId);
        tokenIds.remove(_tokenId);

        UserInfo storage user = userInfo[msg.sender];
        if (user.weightBalance > 0) {
            uint supplyAmount = nftWeightAmount(user.weightBalance, msg.sender); 
            weightTotalSupply = weightTotalSupply.add(supplyAmount).sub(user.weightSupply);
            user.weightSupply = supplyAmount;
        }

        user.rewardDebt = user.weightSupply.mul(rewardPerTokenStored).div(1e18);
        emit WithdrawNFT(msg.sender, _nft, _tokenId);
    }

    function pause() external onlyOwner returns (bool) {
        _pause();
        return true;
    }
    function unpause() external onlyOwner returns (bool) {
        _unpause();
        return true;
    }
    
    function claimUnsupportToken(address _token, address _to, uint _amount) external onlyOwner {
        require(_token != gof, "!safe token");
        require(!supportsNft[_token], "nft!");
        require(_to != address(0), "!safe to");
        IERC20(_token).safeTransfer(_to, _amount);
    }

    function addSupportNft(address _nft) external onlyOwner {
        require(!supportsNft[_nft], "Exists!");
        supportsNft[_nft] = true;
        nfts.push(_nft);
    }

    function claimUnsupportNft(address _nft, address _to, uint256 _tokenId) external onlyOwner {
        require(_nft != gof, "!safe token");
        require(!supportsNft[_nft], "nft!");
        require(_to != address(0), "!safe to");
        IERC721(_nft).transferFrom(address(this), _to, _tokenId);
    }

}