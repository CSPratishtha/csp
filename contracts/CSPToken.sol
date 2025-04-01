// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol"; 
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract CSP_Token is ERC20Burnable, Ownable, ReentrancyGuard {
    IERC20 public USDT_Token;

    enum Phase { NotStarted, PrivateSale, PreSale_1, PreSale_2, PublicSale, Ended }
    Phase public currentPhase = Phase.NotStarted;

    struct PhaseDetails {
        uint256 pricePerToken;
        uint256 allocation;
        uint256 startTime;
        uint256 endTime;
        uint256 lockTime;
        bool isActive;
        bool isStopped;
    }

    struct VestingSchedule {
        uint256 totalAmount;
        uint256 claimedAmount;
        uint256 lockEndTime;
        uint256 unlockPerBatch;
        uint256 lastClaimTime;
    }

    mapping(Phase => PhaseDetails) public phaseDetails;
    mapping(address => uint256) public unlockTime;
    mapping(address => uint256) public userBalances;
    mapping(address => VestingSchedule) public vestingSchedules;

    event PhaseStarted(Phase phase, uint256 startTime, uint256 endTime, uint256 lockTime);
    event PhaseStopped(Phase phase);
    event PhaseResumed(Phase phase);
    event TokensPurchased(address indexed buyer, uint256 usdtAmount, uint256 tokensReceived);
    event USDTWithdrawn(address indexed owner, uint256 amount);
    event TokensTransferred(address indexed sender, address indexed recipient, uint256 amount);
    event TokensVested(address indexed user, uint256 amount);
    event TokensClaimed(address indexed user, uint256 amount);

    uint256 public lockDuration = 2 minutes;
    uint256 public vestingInterval = 1 minutes;

    constructor(address _USDT_Token) ERC20("Chainsphere Token", "CSP") Ownable(msg.sender) {
        require(_USDT_Token != address(0), "Invalid USDT_Token address");
        USDT_Token = IERC20(_USDT_Token);
        _mint(msg.sender, 5_310_000_000 * 10 ** 18);
        initializePhases();
    }

    function initializePhases() internal {
        phaseDetails[Phase.PrivateSale] = PhaseDetails(0.05 ether, 531000000 * 10**18, 0, 0, 0, false, false);
        phaseDetails[Phase.PreSale_1] = PhaseDetails(0.07 ether, 531000000 * 10**18, 0, 0, 0, false, false);
        phaseDetails[Phase.PreSale_2] = PhaseDetails(0.09 ether, 531000000 * 10**18, 0, 0, 0, false, false);
        phaseDetails[Phase.PublicSale] = PhaseDetails(0.12 ether, 265000000 * 10**18, 0, 0, 0, false, false);
    }

    function startPhase(Phase phase, uint256 _startTime, uint256 _endTime, uint256 _lockTime) external onlyOwner {
        require(_startTime < _endTime, "Invalid time range");
        require(!phaseDetails[phase].isActive, "Phase already active");
        phaseDetails[phase].startTime = block.timestamp + _startTime;
        phaseDetails[phase].endTime = block.timestamp + _endTime;
        phaseDetails[phase].lockTime = _lockTime;
        phaseDetails[phase].isActive = true;
        currentPhase = phase;
        emit PhaseStarted(phase, _startTime, _endTime, _lockTime);
    }

   function buyTokens(uint256 usdtAmount) external {
    require(currentPhase == Phase.PrivateSale, "Only Private Sale allows locked tokens");
    require(phaseDetails[currentPhase].isActive, "Phase is not active");
    require(usdtAmount >= 10, "Minimum purchase is 10 USDT");
    require(USDT_Token.allowance(msg.sender, address(this)) >= usdtAmount, "Insufficient USDT allowance");

    PhaseDetails storage phase = phaseDetails[currentPhase];
    uint256 tokensToBuy = (usdtAmount * 10**18) / phase.pricePerToken;
    require(tokensToBuy <= phase.allocation, "Not enough tokens available");

    require(balanceOf(owner()) >= tokensToBuy, "Owner does not have enough tokens");

    USDT_Token.transferFrom(msg.sender, address(this), usdtAmount);
    _transfer(owner(), address(this), tokensToBuy);

    // Update vesting schedule to accumulate purchases
    vestingSchedules[msg.sender].totalAmount += tokensToBuy;
    vestingSchedules[msg.sender].unlockPerBatch = vestingSchedules[msg.sender].totalAmount * 20 / 100;
    vestingSchedules[msg.sender].lockEndTime = block.timestamp + lockDuration;
    vestingSchedules[msg.sender].lastClaimTime = block.timestamp + lockDuration;

    emit TokensVested(msg.sender, tokensToBuy);
    phase.allocation -= tokensToBuy;
}

 
function transferWithLock(address recipient, uint256 amount) external onlyOwner {
    require(balanceOf(owner()) >= amount, "Not enough tokens");
    _transfer(owner(), address(this), amount);

    // Update userBalances mapping
    userBalances[recipient] += amount;

    vestingSchedules[recipient] = VestingSchedule({
        totalAmount: amount,
        claimedAmount: 0,
        lockEndTime: block.timestamp + lockDuration,
        unlockPerBatch: amount * 20 / 100,
        lastClaimTime: block.timestamp + lockDuration
    });
}


    function claimVestedTokens() external {
        VestingSchedule storage schedule = vestingSchedules[msg.sender];
        require(schedule.totalAmount > 0, "No tokens allocated for vesting");
        require(block.timestamp >= schedule.lockEndTime, "Lock period is still active");

        uint256 intervalsPassed = (block.timestamp - schedule.lockEndTime) / vestingInterval;
        uint256 totalUnlocked = intervalsPassed * schedule.unlockPerBatch;
        
        if (totalUnlocked > schedule.totalAmount) {
            totalUnlocked = schedule.totalAmount;
        }
        
        uint256 claimable = totalUnlocked - schedule.claimedAmount;
        require(claimable > 0, "No vested tokens available to claim");
        
        schedule.claimedAmount += claimable;
        schedule.lastClaimTime = block.timestamp;
        _transfer(address(this), msg.sender, claimable);
        
        emit TokensClaimed(msg.sender, claimable);
    }

    function withdrawUSDT(uint256 _amount) external onlyOwner {
        require(_amount > 0, "Invalid amount");
        require(USDT_Token.balanceOf(address(this)) >= _amount, "Insufficient contract balance");
        USDT_Token.transfer(owner(), _amount);
        emit USDTWithdrawn(owner(), _amount);
    }
}
