// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "./interfaces/IPoolFactory.sol";
import "./LinerPool.sol";

contract PoolFactory is IPoolFactory, AccessControl {
    bytes32 public constant MOD = keccak256("MOD");
    bytes32 public constant ADMIN = keccak256("ADMIN");

    address[] private stakeToken_;
    address[] private saleToken_;
    uint256[] private APR_;
    uint256 private startTimeJoin_;
    uint256 private endTimeJoin_;
    uint256 private cap_;
    uint256 private minInvestment_;
    uint256 private maxInvestment_;
    uint256 private lockDuration_;
    address private rewardDistributor_;

    function linerParameters()
        external
        view
        override
        returns (
            address[] memory stakeToken,
            address[] memory saleToken,
            uint256[] memory APR,
            uint256 startTimeJoin,
            uint256 endTimeJoin,
            uint256 cap,
            uint256 minInvestment,
            uint256 maxInvestment,
            uint256 lockDuration,
            address rewardDistributor
        ) {
            return (
                stakeToken_,
                saleToken_,
                APR_,
                startTimeJoin_,
                endTimeJoin_,
                cap_,
                minInvestment_,
                maxInvestment_,
                lockDuration_,
                rewardDistributor_
            );
        }

    constructor() {
        _setRoleAdmin(MOD, ADMIN);
        _setRoleAdmin(ADMIN, ADMIN);
        _setupRole(ADMIN, msg.sender);
        _setupRole(MOD, msg.sender);
    }

    function createLinerPool(
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
    ) external returns (address poolAddress) {
        require(
            hasRole(ADMIN, msg.sender),
            "PoolFactory: require ADMIN role"
        );

        poolAddress = _deploy(
            _stakeToken,
            _saleToken,
            _APR,
            _startTimeJoin,
            _endTimeJoin,
            _cap,
            _minInvestment,
            _maxInvestment,
            _lockDuration,
            _rewardDistributor
        );

        emit LinerPoolCreated(poolAddress);
    }

    function _deploy(
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
    ) private returns (address poolAddress) {

        stakeToken_ = _stakeToken;
        saleToken_ = _saleToken;
        APR_ = _APR;
        startTimeJoin_ = _startTimeJoin;
        endTimeJoin_ = _endTimeJoin;
        cap_ = _cap;
        minInvestment_ = _minInvestment;
        maxInvestment_ = _maxInvestment;
        lockDuration_ = _lockDuration;
        rewardDistributor_ = _rewardDistributor;


        poolAddress = address(new LinearPool());

        delete stakeToken_;
        delete saleToken_;
        delete APR_;
        delete startTimeJoin_;
        delete endTimeJoin_;
        delete cap_;
        delete minInvestment_;
        delete maxInvestment_;
        delete lockDuration_;
        delete rewardDistributor_;
    }
}