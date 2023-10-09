// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

// Import SafeMath library for decimals
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract LoopOfInfinityStaking is Ownable, ReentrancyGuard {
    using SafeMath for uint256;

    // Use SafeMath for decimals
    using SafeMath for uint128;

    // Use SafeMath for decimals
    using SafeMath for uint64;

    IERC20 public token;
    IERC20 public usdtToken; // USDT token contract
    bool public emergencyStop;

    // Define decimals to maintain precision
    uint8 private constant TOKEN_DECIMALS = 18;
    uint8 private constant REWARDS_DECIMALS = 18;

    // Define decimals for penalty and rewards
    uint256 private constant DECIMALS = 10**uint256(TOKEN_DECIMALS + REWARDS_DECIMALS);

    uint256 public constant PENALTY_PERCENTAGE = 10 * 1e18; // Penalty for early withdrawal (10%)
    uint256 public constant SECONDS_IN_MONTH = 30 days;
    uint256 public constant REWARDS_INTERVAL = 30 days;
    uint8 public tokenDecimals;
    uint256 public constant USDT_DECIMALS = 6; // USDT has 6 decimals
    uint256 public constant PRICE_20_PERCENT = 10 * 10**USDT_DECIMALS; // $10 in USDT
    uint256 public constant PRICE_40_PERCENT = 20 * 10**USDT_DECIMALS; // $20 in USDT
    uint256 public constant PRICE_100_PERCENT = 60 * 10**USDT_DECIMALS; // $60 in USDT

    struct Staker {
    uint256 amount;
    uint256 startTime;
    uint256 duration;
    uint256 lastClaimTime;
    uint256 totalRewards;
    uint256 insuranceCoverage;
    uint256 premiumPaid;
    uint256 claimsLeft;
}

    mapping(address => Staker) public stakers;
    mapping(address => bool) public isFirstFiveThousand;
    uint256 public totalStaked;
    uint256 public totalRewardsDistributed;
    uint256 public lastRewardsDistributionTime;

    // Define insurance options
    uint256 public constant INSURANCE_20_PERCENT_COVERAGE = 20;
    uint256 public constant INSURANCE_40_PERCENT_COVERAGE = 40;
    uint256 public constant INSURANCE_100_PERCENT_COVERAGE = 100;

    // Define insurance premium prices in USDT (for example)
    uint256 public constant INSURANCE_PRICE_20_PERCENT = 10 * 1e18; // $10 worth of USDT for 20% coverage
    uint256 public constant INSURANCE_PRICE_40_PERCENT = 20 * 1e18; // $20 worth of USDT for 40% coverage
    uint256 public constant INSURANCE_PRICE_100_PERCENT = 60 * 1e18; // $60 worth of USDT for 100% coverage

    event StakedWithoutInsurance(address indexed user, uint256 amount, uint256 duration);
    event StakedWithInsurance(address indexed user, uint256 amount, uint256 duration, uint256 coveragePercentage);
    event Unstaked(address indexed user, uint256 amount, uint256 penalty, uint256 rewards);
    event RewardsClaimed(address indexed user, uint256 rewards);
    event EmergencyStopSet(bool emergencyStopped);
    event RecoveredFromEmergencyStop(bool recovered);
    event RewardsDistributed(uint256 amount);
    event InsurancePurchased(address indexed user, uint256 coveragePercentage, uint256 premium, uint256 insurancePriceInUSDT);
    event InsuranceClaimed(address indexed user, uint256 claimAmount);
    event RewardsBoughtBack(address indexed user, uint256 tokensBoughtBack, uint256 usdtPaid);
    event RewardsBuyback(address indexed user, uint256 buybackAmount);


     constructor(address _token, uint8 _tokenDecimals, address _usdtToken) {
        token = IERC20(_token);
        tokenDecimals = _tokenDecimals;
        usdtToken = IERC20(_usdtToken);
    }

    modifier notEmergencyStopped() {
        require(!emergencyStop, "Contract is in emergency stop mode");
        _;
    }

    function stakeWithoutInsurance(uint256 amount, uint256 duration) external notEmergencyStopped {
    require(amount > 0, "Amount must be greater than 0");
    require(duration >= 1 && duration <= 12, "Invalid duration");
    require(stakers[msg.sender].amount == 0, "Already staked");

    uint256 stakingDuration = duration * SECONDS_IN_MONTH;

    require(token.balanceOf(msg.sender) >= amount, "Insufficient balance");
    require(token.transferFrom(msg.sender, address(this), amount), "Transfer failed");

    uint256 rewards = calculateRewards(amount, stakingDuration);

    stakers[msg.sender] = Staker({
        amount: amount,
        startTime: block.timestamp,
        duration: duration,
        lastClaimTime: block.timestamp,
        totalRewards: rewards,
        insuranceCoverage: 0, // No insurance for this case
        premiumPaid: 0, // No insurance premium for this case
        claimsLeft: 0
    });

    totalStaked = totalStaked.add(amount);
    totalRewardsDistributed = totalRewardsDistributed.add(rewards);

    emit StakedWithoutInsurance(msg.sender, amount, duration);
}

    function stakeWithInsurance(uint256 amount, uint256 duration, uint256 coverageOption) external notEmergencyStopped {
    require(amount > 0, "Amount must be greater than 0");
    require(duration >= 1 && duration <= 12, "Invalid duration");
    require(coverageOption == INSURANCE_20_PERCENT_COVERAGE ||
            coverageOption == INSURANCE_40_PERCENT_COVERAGE ||
            coverageOption == INSURANCE_100_PERCENT_COVERAGE, "Invalid coverage option");
    require(stakers[msg.sender].amount == 0, "Already staked");

    uint256 stakingDuration = duration * SECONDS_IN_MONTH;

    uint256 insurancePrice;

    if (coverageOption == INSURANCE_20_PERCENT_COVERAGE) {
        insurancePrice = INSURANCE_PRICE_20_PERCENT;
    } else if (coverageOption == INSURANCE_40_PERCENT_COVERAGE) {
        insurancePrice = INSURANCE_PRICE_40_PERCENT;
    } else if (coverageOption == INSURANCE_100_PERCENT_COVERAGE) {
        insurancePrice = INSURANCE_PRICE_100_PERCENT;
    }

    require(token.balanceOf(msg.sender) >= insurancePrice, "Insufficient balance for insurance premium");
    require(token.transferFrom(msg.sender, address(this), insurancePrice), "Insurance premium transfer failed");

    uint256 rewards = calculateRewards(amount, stakingDuration);

    stakers[msg.sender] = Staker({
        amount: amount,
        startTime: block.timestamp,
        duration: duration,
        lastClaimTime: block.timestamp,
        totalRewards: rewards,
        insuranceCoverage: coverageOption, // Include coverage option
        premiumPaid: insurancePrice,
        claimsLeft: 3
    });

    totalStaked = totalStaked.add(amount);
    totalRewardsDistributed = totalRewardsDistributed.add(rewards);

    emit StakedWithInsurance(msg.sender, amount, duration, coverageOption);
    emit InsurancePurchased(msg.sender, coverageOption, insurancePrice, insurancePrice);
}


    function setEmergencyStop(bool _emergencyStop) external onlyOwner {
        emergencyStop = _emergencyStop;
        emit EmergencyStopSet(_emergencyStop);
    }

    function unstake() external notEmergencyStopped nonReentrant {
        Staker storage staker = stakers[msg.sender];
        require(staker.amount > 0, "No stake found");

        uint256 stakingDuration = block.timestamp.sub(staker.startTime);
        uint256 penalty = calculatePenalty(stakingDuration);

        uint256 rewards = staker.totalRewards;
        uint256 withdrawAmount = staker.amount.sub(penalty);

        require(token.transfer(msg.sender, withdrawAmount), "Transfer failed");

        delete stakers[msg.sender];

        totalStaked = totalStaked.sub(staker.amount);

        emit Unstaked(msg.sender, withdrawAmount, penalty, rewards);
    }
  
    function claimInsurance() external notEmergencyStopped nonReentrant {
        Staker storage staker = stakers[msg.sender];
        require(staker.amount > 0, "No stake found");
        require(staker.insuranceCoverage > 0, "Insurance not purchased");
        require(staker.claimsLeft > 0, "No claims left");

        uint256 claimAmount = calculateInsuranceClaim(staker.amount, staker.insuranceCoverage);
        require(token.transfer(msg.sender, claimAmount), "Claim transfer failed");

        staker.claimsLeft--;

        emit InsuranceClaimed(msg.sender, claimAmount);
    }

    function partialUnstake(uint256 amountToUnstake) external notEmergencyStopped nonReentrant {
        Staker storage staker = stakers[msg.sender];
        require(staker.amount > 0, "No stake found");
        require(amountToUnstake > 0 && amountToUnstake <= staker.amount, "Invalid unstake amount");

        uint256 stakingDuration = block.timestamp.sub(staker.startTime);
        uint256 penalty = calculatePenalty(stakingDuration);

        uint256 remainingAmount = staker.amount.sub(penalty);

        require(amountToUnstake <= remainingAmount, "Amount to unstake exceeds remaining staked amount");

        uint256 remainingRewards = calculateRewards(remainingAmount, stakingDuration);
        uint256 unstakeRewards = staker.totalRewards.sub(remainingRewards);

        require(token.transfer(msg.sender, amountToUnstake), "Transfer failed");

        staker.amount = remainingAmount;
        staker.totalRewards = remainingRewards;

        emit Unstaked(msg.sender, amountToUnstake, penalty, unstakeRewards);
    }

    function claimRewards() external notEmergencyStopped nonReentrant {
    Staker storage staker = stakers[msg.sender];
    require(staker.amount > 0, "No stake found");

    uint256 currentTime = block.timestamp;
    uint256 timeElapsed = currentTime.sub(staker.lastClaimTime);
    require(timeElapsed >= REWARDS_INTERVAL, "Cannot claim rewards more frequently than the rewards distribution interval");

    uint256 rewards = calculateRewards(staker.amount, timeElapsed);
    staker.lastClaimTime = currentTime;
    staker.totalRewards = staker.totalRewards.add(rewards);

    // Transfer the rewards to the user
    require(token.transfer(msg.sender, rewards), "Reward transfer failed");

    emit RewardsClaimed(msg.sender, rewards);
}

    function distributeRewards() external onlyOwner notEmergencyStopped nonReentrant {
        require(block.timestamp >= lastRewardsDistributionTime.add(REWARDS_INTERVAL), "Rewards can only be distributed once per interval");

        uint256 rewardsToDistribute = calculateRewardsToDistribute();
        require(rewardsToDistribute > 0, "No rewards to distribute");

        address[] memory stakerAddresses = getAllStakers();
        for (uint256 i = 0; i < stakerAddresses.length; i++) {
            address stakerAddress = stakerAddresses[i];
            Staker storage staker = stakers[stakerAddress];
            uint256 stakerRewards = calculateRewards(staker.amount, block.timestamp.sub(staker.lastClaimTime));
            staker.totalRewards = staker.totalRewards.add(stakerRewards);
            require(token.transfer(stakerAddress, stakerRewards), "Reward transfer failed");
        }

        totalRewardsDistributed = totalRewardsDistributed.add(rewardsToDistribute);
        lastRewardsDistributionTime = block.timestamp;

        emit RewardsDistributed(rewardsToDistribute);
    }

    function calculateRewardsToDistribute() internal view returns (uint256) {
        uint256 totalRewards = 0;
        address[] memory stakerAddresses = getAllStakers();
        for (uint256 i = 0; i < stakerAddresses.length; i++) {
            address stakerAddress = stakerAddresses[i];
            Staker storage staker = stakers[stakerAddress];
            totalRewards = totalRewards.add(calculateRewards(staker.amount, block.timestamp.sub(staker.lastClaimTime)));
        }
        return totalRewards;
    }

    function calculatePenalty(uint256 stakingDuration) internal pure returns (uint256) {
        if (stakingDuration < SECONDS_IN_MONTH) {
            return (stakingDuration.mul(PENALTY_PERCENTAGE)).div(1e18);
        }
        return 0;
    }

    function calculateRewards(uint256 amount, uint256 duration) internal pure returns (uint256) {
        uint256 apy;
        if (duration == SECONDS_IN_MONTH) {
            apy = 23 * 1e18;
        } else if (duration == 3 * SECONDS_IN_MONTH) {
            apy = 33 * 1e18;
        } else if (duration == 6 * SECONDS_IN_MONTH) {
            apy = 43 * 1e18;
        } else {
            apy = 53 * 1e18;
        }
        return (amount.mul(apy).mul(duration)).div(1e36).div(SECONDS_IN_MONTH);
    }

    // Define a variable to represent the precision (e.g., 10000 for 0.1% precision)
    uint256 private constant PRECISION = 10000;

    // Helper function to calculate the insurance premium
    function calculateInsurancePremium(uint256 coverageOption) internal pure returns (uint256) {
    // Ensure coverage option is valid
    require(coverageOption == INSURANCE_20_PERCENT_COVERAGE ||
            coverageOption == INSURANCE_40_PERCENT_COVERAGE ||
            coverageOption == INSURANCE_100_PERCENT_COVERAGE, "Invalid coverage option");

    uint256 insurancePrice;

    if (coverageOption == INSURANCE_20_PERCENT_COVERAGE) {
        insurancePrice = INSURANCE_PRICE_20_PERCENT;
    } else if (coverageOption == INSURANCE_40_PERCENT_COVERAGE) {
        insurancePrice = INSURANCE_PRICE_40_PERCENT;
    } else if (coverageOption == INSURANCE_100_PERCENT_COVERAGE) {
        insurancePrice = INSURANCE_PRICE_100_PERCENT;
    }

    return insurancePrice;
}

 function buyBackTokens() external notEmergencyStopped nonReentrant {
    Staker storage staker = stakers[msg.sender];
    require(staker.amount > 0, "No stake found");
    require(staker.insuranceCoverage > 0, "Insurance not purchased");
    require(staker.claimsLeft > 0, "No claims left");

    uint256 rewardsToBuyBack = calculateRewardsToBuyBack(staker.amount, staker.lastClaimTime);

    // Ensure the project has enough USDT tokens to buy back the rewards
    require(usdtToken.balanceOf(address(this)) >= rewardsToBuyBack, "Insufficient USDT balance for buyback");

    // Transfer USDT tokens to the user
    require(usdtToken.transfer(msg.sender, rewardsToBuyBack), "Buyback transfer of USDT failed");

    // Add the bought-back reward tokens back to the staking contract
    require(token.transferFrom(msg.sender, address(this), rewardsToBuyBack), "Transfer of reward tokens to staking contract failed");

    staker.claimsLeft--;

    emit RewardsBuyback(msg.sender, rewardsToBuyBack);
}

function calculateRewardsToBuyBack(uint256 stakedAmount, uint256 lastClaimTime) internal view returns (uint256) {
    uint256 currentTime = block.timestamp;
    uint256 timeElapsed = currentTime.sub(lastClaimTime);
    uint256 rewardsToBuyBack = calculateRewards(stakedAmount, timeElapsed);
    return rewardsToBuyBack;
}

function calculateBuybackAmount(uint256 rewardsToBuyBack) internal view returns (uint256) {
    // Calculate the buyback amount based on the predetermined price per reward token
    uint256 buybackAmount;
    
    if (isFirstFiveThousandStaker(msg.sender)) {
        // Buy back at a 20% discount for the first five thousand stakers
        buybackAmount = rewardsToBuyBack.mul(PRICE_20_PERCENT).div(DECIMALS);
    } else {
        // Buy back at the regular price for the rest of the stakers
        buybackAmount = rewardsToBuyBack.mul(PRICE_40_PERCENT).div(DECIMALS);
    }

    return buybackAmount;
}

// Function to check if an address is one of the first five thousand stakers
function isFirstFiveThousandStaker(address stakerAddress) internal view returns (bool) {
    return isFirstFiveThousand[stakerAddress];
}

    // Helper function to calculate the insurance claim amount in the staked token
    function calculateInsuranceClaim(uint256 stakeAmount, uint256 coveragePercentage) internal view returns (uint256) {
    // Ensure coverage percentage is within a reasonable range (0-100%)
    require(coveragePercentage <= 100, "Invalid coverage percentage");

    // Calculate the claim amount based on the stake amount and coverage percentage
    uint256 claimAmount = (stakeAmount * coveragePercentage) / PRECISION;

    // Ensure the claim amount is within a reasonable range (0-100%)
    require(claimAmount <= PRECISION, "Invalid claim amount");

    // Calculate the equivalent claim amount in the staked token
    uint256 equivalentClaimAmount = (claimAmount * 10**uint256(tokenDecimals)) / PRECISION;

    return equivalentClaimAmount;
}

   // View function to get the contract's token balance
    function getTokenBalance() external view returns (uint256) {
        return token.balanceOf(address(this));
    }

    // View function to get the contract's USDT balance
    function getUsdtBalance() external view returns (uint256) {
        return usdtToken.balanceOf(address(this));
    }

    // Function to recover from the emergency stop, can only be called by the owner
    function recoverFromEmergencyStop() external onlyOwner {
        require(emergencyStop, "Contract is not in emergency stop mode");
        emergencyStop = false;
        emit RecoveredFromEmergencyStop(true);
    }

    function getStakerDetails(address user) external view returns (Staker memory) {
        return stakers[user];
    }

    function getTotalStaked() external view returns (uint256) {
        return totalStaked;
    }

    function getTotalRewardsDistributed() external view returns (uint256) {
        return totalRewardsDistributed;
    }

    function getNumberOfStakers() external view returns (uint256) {
        return getAllStakers().length;
    }

    function getAllStakers() public view returns (address[] memory) {
    uint256 count = 0;
    address[] memory addresses = new address[](totalStaked);

    for (uint256 i = 0; i < totalStaked; i++) {
        address stakerAddress = addresses[i];
        if (stakers[stakerAddress].amount > 0) {
            addresses[count] = stakerAddress;
            count++;
        }
    }

    // Resize the addresses array to the actual count
    assembly {
        mstore(addresses, count)
    }

    return addresses;
}

 // Fallback function to receive Ether (if accidentally sent)
    receive() external payable {
        revert("This contract does not accept Ether.");
    }
}
