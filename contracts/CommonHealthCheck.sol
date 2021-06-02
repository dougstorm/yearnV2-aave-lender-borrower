// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.6.0 <0.7.0;
pragma experimental ABIEncoderV2;

struct StrategyParams {
    uint256 performanceFee;
    uint256 activation;
    uint256 debtRatio;
    uint256 minDebtPerHarvest;
    uint256 maxDebtPerHarvest;
    uint256 lastReport;
    uint256 totalDebt;
    uint256 totalGain;
    uint256 totalLoss;
}

interface VaultAPI {
    function strategies(address _strategy)
        external
        view
        returns (StrategyParams memory);
}

interface StrategyAPI {
    function vault() external view returns (address);
}

interface CustomHealthCheck {
    function check(
        uint256 profit,
        uint256 loss,
        uint256 debtPayment,
        uint256 debtOutstanding,
        address callerStrategy
    ) external view returns (bool);
}

// LEGACY INTERFACES PRE 0.3.2
struct LegacyStrategyParams {
    uint256 performanceFee;
    uint256 activation;
    uint256 debtRatio;
    uint256 rateLimit;
    uint256 lastReport;
    uint256 totalDebt;
    uint256 totalGain;
    uint256 totalLoss;
}

interface LegacyVaultAPI {
    function strategies(address _strategy)
        external
        view
        returns (LegacyStrategyParams memory);
}

contract CommonHealthCheck {
    // Global Settings for all strategies
    uint256 constant MAX_BPS = 10_000;
    uint256 public profitLimitRatio;
    uint256 public lossLimitRatio;

    address public governance;
    address public management;

    mapping(address => address) public checks;

    modifier onlyGovernance() {
        require(msg.sender == governance, "!authorized");
        _;
    }

    modifier onlyAuthorized() {
        require(
            msg.sender == governance || msg.sender == management,
            "!authorized"
        );
        _;
    }

    constructor(address _vault) public {
        governance = msg.sender;
        management = msg.sender;
    }

    function setGovernance(address _governance) external onlyGovernance {
        require(_governance != address(0));
        governance = _governance;
    }

    function setManagement(address _management) external onlyGovernance {
        require(_management != address(0));
        management = _management;
    }

    function setCheck(address _strategy, address _check)
        external
        onlyAuthorized
    {
        checks[_strategy] = _check;
    }

    function check(
        uint256 profit,
        uint256 loss,
        uint256 debtPayment,
        uint256 debtOutstanding
    ) external view returns (bool) {
        address vault = StrategyAPI(msg.sender).vault();
        uint256 totalDebt = VaultAPI(vault).strategies(address(this)).totalDebt;

        return
            _runChecks(profit, loss, debtPayment, debtOutstanding, totalDebt);
    }

    // unfortunately we need a different method to interact with 0.3.0 vaults that are in prod because
    // of different interfaces
    function checkLegacy(
        uint256 profit,
        uint256 loss,
        uint256 debtPayment,
        uint256 debtOutstanding
    ) external view returns (bool) {
        address vault = StrategyAPI(msg.sender).vault();
        uint256 totalDebt =
            LegacyVaultAPI(vault).strategies(address(this)).totalDebt;

        return
            _runChecks(profit, loss, debtPayment, debtOutstanding, totalDebt);
    }

    function _runChecks(
        uint256 profit,
        uint256 loss,
        uint256 debtPayment,
        uint256 debtOutstanding,
        uint256 totalDebt
    ) internal view returns (bool) {
        address customCheck = checks[msg.sender];

        if (customCheck == address(0)) {
            return _executeDefaultCheck(profit, loss, totalDebt);
        }

        return
            CustomHealthCheck(customCheck).check(
                profit,
                loss,
                debtPayment,
                debtOutstanding,
                msg.sender
            );
    }

    function _executeDefaultCheck(
        uint256 _profit,
        uint256 _loss,
        uint256 _totalDebt
    ) internal view returns (bool) {
        if (_profit <= (_totalDebt * profitLimitRatio) / MAX_BPS) {
            return false;
        }
        if (_loss <= (_totalDebt * lossLimitRatio) / MAX_BPS) {
            return false;
        }
        // health checks pass
        return true;
    }
}
