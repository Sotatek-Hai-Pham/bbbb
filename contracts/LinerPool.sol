//SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "./interfaces/IPoolFactory.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/IAccessControl.sol";

contract LinearPool is
    ReentrancyGuard,
    Pausable
{
    using SafeERC20 for IERC20;

    bytes32 public constant MOD = keccak256("MOD");
    bytes32 public constant ADMIN = keccak256("ADMIN");
    uint32 private constant ONE_YEAR_IN_SECONDS = 365 days;

    uint8 public MAX_NUMBER_TOKEN = 5;

    // Pool creator
    address public immutable factory;
    // The accepted token
    IERC20[] public linearAcceptedToken;
    // Reward token
    IERC20[] public linearRewardToken;
    // The reward distribution address
    address public linearRewardDistributor;
    // Totak capacity of this pool
    uint256 cap;
    // Max tokens an user can stake into this
    uint256 maxInvestment;
    // Min tokens an user must stake into this
    uint256 minInvestment;
    // APR of this pool
    uint256[] APR;
    // Lock time to claim reward after staked
    uint256 lockDuration;
    // Can stake time
    uint256 startJoinTime;
    // End of stake time
    uint256 endJoinTime;

    // Info of each user that stakes in pool
    mapping(address => LinearStakingData) public linearStakingData;
    // Allow emergency withdraw feature
    bool public linearAllowEmergencyWithdraw;

    event LinearDeposit(address indexed account, uint256[] amount);
    event LinearWithdraw(address indexed account, uint256[] amount);
    event LinearRewardsHarvested(address indexed account, uint256[] reward);
    event LinearPendingWithdraw(address indexed account, uint256[] amount);
    event LinearEmergencyWithdraw(address indexed account, uint256[] amount);

    struct LinearStakingData {
        uint256[] balance;
        uint256 joinTime;
        uint256 updatedTime;
        uint256[] reward;
    }

    event LinearAddWhitelist(address account);
    event LinearRemoveWhitelist(address account);

    event LinearSetDelayDuration(uint256 duration);

    event AssignStakingData(address from, address to);
    event AdminRecoverFund(address token, address to, uint256 amount);

    modifier isMod() {
        require(
            IAccessControl(factory).hasRole(MOD, msg.sender),
            "LinearStakingPool: forbidden"
        );
        _;
    }

    modifier isAdmin() {
        require(
            IAccessControl(factory).hasRole(ADMIN, msg.sender),
            "LinearStakingPool: forbidden"
        );
        _;
    }

    /**
     * @notice Initialize the contract, get called in the first time deploy
     */
    constructor() {
        (
            address[] memory _stakeToken,
            address[] memory _saleToken,
            uint256[] memory _APR,
            uint256 _startTimeJoin,
            uint256 _endTimeJoin,
            uint256 _cap,
            uint256 _minInvestment,
            uint256 _maxInvestment,
            uint256 _lockDuration,
            address _rewardDistributor
        ) = IPoolFactory(msg.sender).linerParameters();

        uint256 _rewardLength = _stakeToken.length;
        require(
            _rewardLength <= MAX_NUMBER_TOKEN,
            "LinearStakingPool: inffuse token numbers"
        );
        require(
            _startTimeJoin >= block.timestamp && _endTimeJoin > _startTimeJoin,
            "LinearStakingPool: invalid end join time"
        );

        require(
            _maxInvestment >= _minInvestment,
            "LinearStakingPool: Invalid investment value"
        );

        require(
            _rewardLength == _saleToken.length && _rewardLength == _APR.length,
            "LinearStakingPool: invalid token length"
        );

        for (uint8 i = 0; i < _rewardLength; ) {
            require(
                _saleToken[i] != address(0) && _stakeToken[i] != address(0),
                "LinearStakingPool: invalid token address"
            );
            linearAcceptedToken[i] = IERC20(_stakeToken[i]);
            linearRewardToken[i] = IERC20(_saleToken[i]);
            APR[i] = _APR[i];

            unchecked {
                i++;
            }
        }

        factory = msg.sender;
        startJoinTime = _startTimeJoin;
        endJoinTime = _endTimeJoin;
        cap = _cap;
        minInvestment = _minInvestment;
        maxInvestment = _maxInvestment;
        lockDuration = _lockDuration;
        linearRewardDistributor = _rewardDistributor;

    }

    /**
     * @notice Pause contract
     */
    function pauseContract() external isMod  {
        _pause();
    }

    /**
     * @notice Unpause contract
     */
    function unpauseContract() external isMod {
        _unpause();
    }

    /**
     * @notice Admin withdraw tokens from a contract
     * @param _token token to withdraw
     * @param _to to user address
     * @param _amount amount to withdraw
     */
    function linearAdminRecoverFund(
        address _token,
        address _to,
        uint256 _amount
    ) external isAdmin {
        IERC20(_token).safeTransfer(_to, _amount);
        emit AdminRecoverFund(_token, _to, _amount);
    }

    /**
     * @notice Set the reward distributor. Can only be called by the owner.
     * @param _linearRewardDistributor the reward distributor
     */
    function linearSetRewardDistributor(address _linearRewardDistributor)
        external
        isAdmin
    {
        require(
            _linearRewardDistributor != address(0),
            "LinearStakingPool: invalid reward distributor"
        );
        linearRewardDistributor = _linearRewardDistributor;
    }
    

    /**
     * @notice Set max numbers the rewards Can only be called by the owner.
     * @param _num the reward distributor
     */
    function linearSetRewardDistributor(uint8 _num)
        external
        isAdmin
    {
        
        MAX_NUMBER_TOKEN = _num;
    }

    /**
     * @notice Deposit token to earn rewards
     * @param _amount amount of token to deposit
     */
    function linearDeposit(uint256[] memory _amount)
        external
        nonReentrant
        whenNotPaused
    {
        address account = msg.sender;

        _linearDeposit(_amount, account);

        for(uint8 i=0; i<_amount.length; i++) {
            linearAcceptedToken[i].safeTransferFrom(account, address(this), _amount[i]);
        }
        emit LinearDeposit(account, _amount);
    }

    /**
     * @notice Deposit token to earn rewards
     * @param _amount amount of token to deposit
     * @param _receiver receiver
     */
    function linearDepositSpecifyReceiver(uint256[] memory _amount, address _receiver)
        external
        nonReentrant
        whenNotPaused
    {
        _linearDeposit(_amount, _receiver);

        for(uint8 i=0; i<_amount.length; i++) {
            linearAcceptedToken[i].safeTransferFrom(msg.sender, address(this), _amount[i]);
        }
        emit LinearDeposit(_receiver, _amount);
    }

    /**
     * @notice Withdraw token from a pool
     * @param _amount amount to withdraw
     */
    function linearWithdraw(uint256[] memory _amount)
        external
        nonReentrant
        whenNotPaused
    {
        address account = msg.sender;
        LinearStakingData storage stakingData = linearStakingData[account];

        require(
            block.timestamp >= stakingData.joinTime + lockDuration,
            "LinearStakingPool: still locked"
        );

        require(
            stakingData.balance.length > 0,
            "LinearStakingPool: nothing to withdraw"
        );

        _linearHarvest(account);
        uint256[] memory _rewards = new uint256[](stakingData.balance.length);
        require(
            linearRewardDistributor != address(0),
            "LinearStakingPool: invalid reward distributor"
        );

        for(uint8 i=0; i<stakingData.balance.length; i++) {

            require(
                stakingData.reward[i] >= _amount[i],
                "LinearStakingPool: invalid withdraw amount"
            );

            if (stakingData.reward[i] > 0) {

                uint256 reward = stakingData.reward[i];
                stakingData.reward[i] = 0;
                linearRewardToken[i].safeTransferFrom(
                    linearRewardDistributor,
                    account,
                    reward
                );
                _rewards[i] = reward;
            }

            stakingData.balance[i] -= _amount[i];
            linearAcceptedToken[i].safeTransfer(account, _amount[i]);
        }

        emit LinearRewardsHarvested(account, _rewards);
        emit LinearWithdraw(account, _amount);
    }

    /**
     * @notice Claim reward token from a pool
     */
    function linearClaimReward() external nonReentrant whenNotPaused {
        address account = msg.sender;
        LinearStakingData storage stakingData = linearStakingData[account];

        require(
            block.timestamp >= stakingData.joinTime + lockDuration,
            "LinearStakingPool: still locked"
        );

        _linearHarvest(account);
        uint256[] memory _rewards = new uint256[](stakingData.balance.length);
        require(
            linearRewardDistributor != address(0),
            "LinearStakingPool: invalid reward distributor"
        );

        for(uint8 i=0; i<stakingData.balance.length; i++) {
        
            if (stakingData.reward[i] > 0) {
                uint256 reward = stakingData.reward[i];
                stakingData.reward[i] = 0;
                linearRewardToken[i].safeTransferFrom(
                    linearRewardDistributor,
                    account,
                    reward
                );
                _rewards[i] = reward;
            }        
        }
        emit LinearRewardsHarvested(account, _rewards);
    }

    /**
     * @notice Gets number of reward tokens of a user from a pool
     * @param _account address of a user
     * @return rewards earned reward of a user
     */
    function linearPendingReward(address _account)
        public
        view
        returns (uint256[] memory rewards)
    {
        LinearStakingData storage stakingData = linearStakingData[_account];

        uint256 startTime = stakingData.updatedTime > 0
            ? stakingData.updatedTime
            : block.timestamp;

        uint256 endTime = block.timestamp;
        if (
            lockDuration > 0 &&
            stakingData.joinTime + lockDuration < block.timestamp
        ) {
            endTime = stakingData.joinTime + lockDuration;
        }

        uint256 stakedTimeInSeconds = endTime > startTime
            ? endTime - startTime
            : 0;

        if (stakedTimeInSeconds > lockDuration)
            stakedTimeInSeconds = lockDuration;
        rewards = new uint256[](stakingData.balance.length);
        for (uint8 i = 0; i < stakingData.balance.length; i++) {
            uint256 pendingReward = ((stakingData.balance[i] *
                stakedTimeInSeconds *
                APR[i]) / ONE_YEAR_IN_SECONDS) / 1e20;
            rewards[i] = stakingData.reward[i] + pendingReward;
        }
    }

    /**
     * @notice Gets number of deposited tokens in a pool
     * @param _account address of a user
     * @return total token deposited in a pool by a user
     */
    function linearBalanceOf(address _account) external view returns (uint256[] memory) {
        return linearStakingData[_account].balance;
    }

    /**
     * @notice Gets number of deposited tokens in a pool
     * @param _account address of a user
     * @return total token deposited in a pool by a user
     */
    function linearUserStakingData(address _account)
        external
        view
        returns (LinearStakingData memory)
    {
        return linearStakingData[_account];
    }

    /**
     * @notice Update allowance for emergency withdraw
     * @param _shouldAllow should allow emergency withdraw or not
     */
    function linearSetAllowEmergencyWithdraw(bool _shouldAllow)
        external
        
    {
        linearAllowEmergencyWithdraw = _shouldAllow;
    }

    /**
     * @notice Withdraw without caring about rewards. EMERGENCY ONLY.
     */
    function linearEmergencyWithdraw() external nonReentrant whenNotPaused {
        require(
            linearAllowEmergencyWithdraw,
            "LinearStakingPool: emergency withdrawal is not allowed yet"
        );

        address account = msg.sender;
        LinearStakingData storage stakingData = linearStakingData[account];

        require(
            stakingData.balance.length > 0,
            "LinearStakingPool: nothing to withdraw"
        );

        uint256[] memory amount = stakingData.balance;

        stakingData.balance = new uint256[](stakingData.balance.length);
        stakingData.reward = new uint256[](stakingData.balance.length);
        stakingData.updatedTime = block.timestamp;

        for(uint8 i=0; i< amount.length; i++) {
            linearAcceptedToken[i].safeTransfer(account, amount[i]);
        }
        emit LinearEmergencyWithdraw(account, amount);
    }

    function _linearDeposit(uint256[] memory _amount, address account)
        internal
    {
        LinearStakingData storage stakingData = linearStakingData[account];

        require(
            _amount.length == stakingData.balance.length,
            "LinearStakingPool: inffuse amounts"
        );

        require(
            block.timestamp >= startJoinTime,
            "LinearStakingPool: pool is not started yet"
        );

        require(
            block.timestamp <= endJoinTime,
            "LinearStakingPool: pool is already closed"
        );

        _linearHarvest(account);

        for(uint8 i=0; i< _amount.length; i++){
            stakingData.balance[i] += _amount[i];
        }
        stakingData.joinTime = block.timestamp;
    }

    function _linearHarvest(address _account) private {
        LinearStakingData storage stakingData = linearStakingData[_account];
        uint256 _length = stakingData.balance.length;
        if (_length == 0) {
            uint256[] memory _tempArr = new uint256[](_length);
            stakingData.balance = _tempArr;
            stakingData.reward = _tempArr;
        }

        stakingData.reward = linearPendingReward(_account);
        stakingData.updatedTime = block.timestamp;
    }
}
