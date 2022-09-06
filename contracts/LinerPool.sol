//SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "./interfaces/IPoolFactory.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeCastUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/structs/EnumerableSetUpgradeable.sol";

contract LinearPool is
    Initializable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable
{
    using SafeERC20 for IERC20;
    using SafeCastUpgradeable for uint256;
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.UintSet;

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

    event LinearDeposit(
        address indexed account,
        uint256 amount
    );
    event LinearWithdraw(
        address indexed account,
        uint256 amount
    );
    event LinearRewardsHarvested(
        address indexed account,
        uint256 reward
    );
    event LinearPendingWithdraw(
        address indexed account,
        uint256 amount
    );
    event LinearEmergencyWithdraw(
        address indexed account,
        uint256 amount
    );


    struct LinearStakingData {
        uint256[] balance;
        uint256 joinTime;
        uint256 updatedTime;
        uint256[] reward;
    }


    event LinearClaimPendingWithdraw(
        address account,
        uint256 amount
    );


    event LinearAddWhitelist(address account);
    event LinearRemoveWhitelist(address account);

    event LinearSetDelayDuration(uint256 duration);

    event AssignStakingData(address from, address to);
    event AdminRecoverFund(address token, address to, uint256 amount);


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
        require(_rewardLength <= MAX_NUMBER_TOKEN,
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
            _rewardLength == _saleToken.length && _rewardLength == _APR.length ,
            "LinearStakingPool: invalid token length"
        );

        for(uint8 i=0; i<_rewardLength; ) {
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
    function pauseContract() public onlyOwner {
        _pause();
    }

    /**
     * @notice Unpause contract
     */
    function unpauseContract() external onlyOwner {
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
    ) external onlyOwner {
        IERC20(_token).safeTransfer(_to, _amount);
        emit AdminRecoverFund(_token, _to, _amount);
    }

    /**
     * @notice Set the reward distributor. Can only be called by the owner.
     * @param _linearRewardDistributor the reward distributor
     */
    function linearSetRewardDistributor(address _linearRewardDistributor)
        external
        onlyOwner
    {
        require(
            _linearRewardDistributor != address(0),
            "LinearStakingPool: invalid reward distributor"
        );
        linearRewardDistributor = _linearRewardDistributor;
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

        linearAcceptedToken.safeTransferFrom(account, address(this), _amount);
        emit LinearDeposit(account, _amount);
    }

    /**
     * @notice Deposit token to earn rewards
     * @param _amount amount of token to deposit
     * @param _receiver receiver
     */
    function linearDepositSpecifyReceiver(
        uint256 _amount,
        address _receiver
    ) external nonReentrant whenNotPaused {
        _linearDeposit(_amount, _receiver);

        linearAcceptedToken.safeTransferFrom(
            msg.sender,
            address(this),
            _amount
        );
        emit LinearDeposit(_receiver, _amount);
    }

    /**
     * @notice Withdraw token from a pool
     * @param _amount amount to withdraw
     */
    function linearWithdraw(uint256 _amount)
        external
        nonReentrant
        whenNotPaused
    {
        address account = msg.sender;
        LinearStakingData storage stakingData = linearStakingData[
            account
        ];

        require(
            block.timestamp >= stakingData.joinTime + lockDuration,
            "LinearStakingPool: still locked"
        );

        require(
            stakingData.balance >= _amount,
            "LinearStakingPool: invalid withdraw amount"
        );

        _linearHarvest(account);

        if (stakingData.reward > 0) {
            require(
                linearRewardDistributor != address(0),
                "LinearStakingPool: invalid reward distributor"
            );

            uint256 reward = stakingData.reward;
            stakingData.reward = 0;
            linearAcceptedToken.safeTransferFrom(
                linearRewardDistributor,
                account,
                reward
            );
            emit LinearRewardsHarvested( account, reward);
        }


        stakingData.balance -= _amount;
        linearAcceptedToken.safeTransfer(account, _amount);

        emit LinearWithdraw(account, _amount);
    }

    /**
     * @notice Withdraw token from a pool
     */
    function linearWithdrawAll()
        external
        nonReentrant
        whenNotPaused
    {
        address account = msg.sender;
        LinearStakingData storage stakingData = linearStakingData[
            account
        ];

        require(
            block.timestamp >= stakingData.joinTime + lockDuration,
            "LinearStakingPool: still locked"
        );

        require(
            stakingData.balance >= 0,
            "LinearStakingPool: invalid withdraw amount"
        );

        _linearHarvest(account);

        if (stakingData.reward > 0) {
            require(
                linearRewardDistributor != address(0),
                "LinearStakingPool: invalid reward distributor"
            );

            uint256 reward = stakingData.reward;
            stakingData.reward = 0;
            linearAcceptedToken.safeTransferFrom(
                linearRewardDistributor,
                account,
                reward
            );
            emit LinearRewardsHarvested(account, reward);
        }

        uint256 withdrawBalance = stakingData.balance;
        stakingData.balance = 0;
        linearAcceptedToken.safeTransfer(account, withdrawBalance);

        emit LinearWithdraw(account, withdrawBalance);
    }

    /**
     * @notice Claim reward token from a pool
     */
    function linearClaimReward()
        external
        nonReentrant
        whenNotPaused
    {
        address account = msg.sender;
        LinearStakingData storage stakingData = linearStakingData[
            account
        ];

        require(
            block.timestamp >= stakingData.joinTime + lockDuration,
            "LinearStakingPool: still locked"
        );

        _linearHarvest(account);

        if (stakingData.reward > 0) {
            require(
                linearRewardDistributor != address(0),
                "LinearStakingPool: invalid reward distributor"
            );
            uint256 reward = stakingData.reward;
            stakingData.reward = 0;
            linearAcceptedToken.safeTransferFrom(
                linearRewardDistributor,
                account,
                reward
            );
            emit LinearRewardsHarvested(account, reward);
        }
    }

    /**
     * @notice Gets number of reward tokens of a user from a pool
     * @param _account address of a user
     * @return reward earned reward of a user
     */
    function linearPendingReward(address _account)
        public
        view
        returns (uint256[] memory reward)
    {
        LinearStakingData storage stakingData = linearStakingData[
            _account
        ];

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

        uint256 pendingReward = ((stakingData.balance *
            stakedTimeInSeconds *
            APR) / ONE_YEAR_IN_SECONDS) / 100;

        reward = stakingData.reward + pendingReward;
    }

    /**
     * @notice Gets number of deposited tokens in a pool
     * @param _account address of a user
     * @return total token deposited in a pool by a user
     */
    function linearBalanceOf( address _account)
        external
        view
        returns (uint256)
    {
        return linearStakingData[_account].balance;
    }

    /**
     * @notice Gets number of deposited tokens in a pool
     * @param _account address of a user
     * @return total token deposited in a pool by a user
     */
    function linearUserStakingData( address _account)
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
        onlyOwner
    {
        linearAllowEmergencyWithdraw = _shouldAllow;
    }

    /**
     * @notice Withdraw without caring about rewards. EMERGENCY ONLY.
     */
    function linearEmergencyWithdraw()
        external
        nonReentrant
        whenNotPaused
    {
        require(
            linearAllowEmergencyWithdraw,
            "LinearStakingPool: emergency withdrawal is not allowed yet"
        );

        address account = msg.sender;
        LinearStakingData storage stakingData = linearStakingData[
            account
        ];

        require(
            stakingData.balance > 0,
            "LinearStakingPool: nothing to withdraw"
        );

        uint256 amount = stakingData.balance;

        stakingData.balance = 0;
        stakingData.reward = 0;
        stakingData.updatedTime = block.timestamp;

        linearAcceptedToken.safeTransfer(account, amount);
        emit LinearEmergencyWithdraw( account, amount);
    }

    function _linearDeposit(
        uint256[] memory _amount,
        address account
    ) internal {
        LinearStakingData storage stakingData = linearStakingData[
            account
        ];

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

        stakingData.balance += _amount;
        stakingData.joinTime = block.timestamp;

    }

    function _linearHarvest(address _account) private {
        LinearStakingData storage stakingData = linearStakingData[
            _account
        ];

        stakingData.reward = linearPendingReward(_account);
        stakingData.updatedTime = block.timestamp;
    }

}