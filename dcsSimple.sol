// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract SimplifiedLoanAndRiskPoolContract is Ownable, ReentrancyGuard {
    struct Loan {
        address borrower;
        uint256 amount;
        uint256 dueDate;
        bool isRepaid;
        uint256 poolId;
    }

    struct CreditScore {
        uint256 score;
        uint256 lastUpdateTimestamp;
    }

    struct RiskPool {
        uint256 totalFunds;
        uint256 availableFunds;
        uint256 riskLevel;
        // uint256 customValue;
    }

    mapping(uint256 => Loan) public loans;
    mapping(address => CreditScore) private creditScores;
    mapping(uint256 => RiskPool) public riskPools;
    uint256 public nextLoanId;
    uint256 public poolCount;

    uint256 public constant MIN_CREDIT_SCORE = 300;
    uint256 public constant INITIAL_CREDIT_SCORE = 500;

    event LoanCreated(uint256 indexed loanId, address indexed borrower, uint256 amount, uint256 dueDate, uint256 poolId);
    event LoanRepaid(uint256 indexed loanId, address indexed borrower, uint256 amount);
    event CreditScoreUpdated(address indexed user, uint256 newScore);
    event PoolCreated(uint256 indexed poolId, uint256 riskLevel, uint256 initialFunds);
    event FundsAdded(uint256 indexed poolId, uint256 amount);

    constructor() Ownable(msg.sender) {
        nextLoanId = 0;
        poolCount = 0;
    }

    function createRiskPool(uint256 _riskLevel, uint256 _initialFunds) external payable onlyOwner {
        require(_riskLevel > 0 && _riskLevel <= 100, "Risk level must be between 1 and 100");
        
        uint256 initialFunds = _initialFunds;
        if (msg.value > 0) {
            require(msg.value == _initialFunds, "Sent value does not match specified initial funds");
            initialFunds = msg.value;
        }

        uint256 poolId = poolCount++;
        riskPools[poolId] = RiskPool({
            totalFunds: initialFunds,
            availableFunds: initialFunds,
            riskLevel: _riskLevel
            // customValue: _customValue
        });

        emit PoolCreated(poolId, _riskLevel, initialFunds);
    }

    function addFundsToPool(uint256 _poolId, uint256 _amount) external payable {
        require(_poolId < poolCount, "Invalid pool ID");
        // require(msg.value == _amount, "Sent value does not match specified amount");
        require(_amount > 0, "Must send funds");

        RiskPool storage pool = riskPools[_poolId];
        pool.totalFunds += _amount;
        pool.availableFunds += _amount;

        emit FundsAdded(_poolId, _amount);
    }

    function requestLoan(uint256 loanAmount, uint256 duration) external nonReentrant {
        require(loanAmount > 0, "Loan amount must be greater than 0");
        require(duration > 0, "Loan duration must be greater than 0");

        uint256 creditScore = getCreditScore(msg.sender);
        require(creditScore >= MIN_CREDIT_SCORE, "Credit score too low for a loan");

        uint256 poolId = assignRiskPool(creditScore, loanAmount);
        require(poolId < poolCount, "No suitable risk pool found");

        RiskPool storage pool = riskPools[poolId];
        require(pool.availableFunds >= loanAmount, "Insufficient funds in the selected pool");

        uint256 loanId = nextLoanId++;
        loans[loanId] = Loan({
            borrower: msg.sender,
            amount: loanAmount,
            dueDate: block.timestamp + duration,
            isRepaid: false,
            poolId: poolId
        });

        pool.availableFunds -= loanAmount;

        emit LoanCreated(loanId, msg.sender, loanAmount, block.timestamp + duration, poolId);

        // Transfer the loan amount to the borrower
        payable(msg.sender).transfer(loanAmount);
    }


    function repayLoan(uint256 loanId) external payable nonReentrant {
        Loan storage loan = loans[loanId];
        require(msg.sender == loan.borrower, "Only borrower can repay the loan");
        require(!loan.isRepaid, "Loan already repaid");
        require(msg.value >= loan.amount, "Insufficient repayment amount");

        loan.isRepaid = true;
        updateCreditScore(msg.sender, true);

        RiskPool storage pool = riskPools[loan.poolId];
        pool.availableFunds += loan.amount;

        emit LoanRepaid(loanId, msg.sender, loan.amount);

        if (msg.value > loan.amount) {
            payable(msg.sender).transfer(msg.value - loan.amount);
        }
    }

    function getCreditScore(address user) public view returns (uint256) {
        if (creditScores[user].score == 0) {
            return INITIAL_CREDIT_SCORE;
        }
        return creditScores[user].score;
    }

    function updateCreditScore(address user, bool isPositive) internal {
        CreditScore storage userScore = creditScores[user];
        if (userScore.score == 0) {
            userScore.score = INITIAL_CREDIT_SCORE;
        }

        if (isPositive) {
            userScore.score = min(userScore.score + 10, 850);
        } else {
            userScore.score = max(userScore.score - 50, 300);
        }

        userScore.lastUpdateTimestamp = block.timestamp;
        emit CreditScoreUpdated(user, userScore.score);
    }

    function assignRiskPool(uint256 creditScore, uint256 amount) internal view returns (uint256) {
        uint256 selectedPoolId = 0;
        uint256 bestMatch = type(uint256).max;

        for (uint256 i = 0; i < poolCount; i++) {
            RiskPool storage pool = riskPools[i];
            if (pool.availableFunds >= amount) {
                uint256 scoreDiff = creditScore > pool.riskLevel ? creditScore - pool.riskLevel : pool.riskLevel - creditScore;
                if (scoreDiff < bestMatch) {
                    bestMatch = scoreDiff;
                    selectedPoolId = i;
                }
            }
        }

        return selectedPoolId;
    }

    function getPoolDetails(uint256 _poolId) external view returns (uint256, uint256, uint256) {
        require(_poolId < poolCount, "Invalid pool ID");
        RiskPool storage pool = riskPools[_poolId];
        return (pool.totalFunds, pool.availableFunds, pool.riskLevel);
    }

    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    function max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a : b;
    }
}