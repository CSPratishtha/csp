// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract CSPToken is ERC20Burnable {
    uint256 public constant INITIAL_SUPPLY = 5_310_000_000 * 10 ** 18;

    constructor() ERC20("Chainsphere Token", "CSP") {
        _mint(msg.sender, INITIAL_SUPPLY);
    }
}

contract ICO is Ownable, ReentrancyGuard {
    IERC20 public CSP;
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

    mapping(Phase => PhaseDetails) public phaseDetails;
    mapping(address => uint256) public unlockTime;
    mapping(address => uint256) public userBalances;
    mapping(address => bool) public whitelisted;
    mapping(address => uint256) public referrals;
    mapping(address => uint256) public purchaseHistory;

    event PhaseStarted(Phase phase, uint256 startTime, uint256 endTime, uint256 lockTime);
    event PhaseStopped(Phase phase);
    event PhaseResumed(Phase phase);
    event TokensPurchased(address indexed buyer, uint256 usdtAmount, uint256 tokensReceived);
    event USDTWithdrawn(address indexed owner, uint256 amount);
    event TokensTransferred(address indexed sender, address indexed recipient, uint256 amount);
    event ReferralRewarded(address indexed referrer, address indexed referee, uint256 reward);
    event WhitelistUpdated(address indexed user, bool status);
    event PhaseChanged(Phase newPhase);

    constructor(address _USDT_Token, address _CSP_Token) Ownable(msg.sender) {
        require(_USDT_Token != address(0), "Invalid USDT_Token address");
        require(_CSP_Token != address(0), "Invalid CSP_Token address");

        USDT_Token = IERC20(_USDT_Token);
        CSP = IERC20(_CSP_Token);
        initializePhases();
    }

    function initializePhases() internal {
        phaseDetails[Phase.PrivateSale] = PhaseDetails(0.05 ether, 531_000_000 * 10**18, 0, 0, 0, false, false);
        phaseDetails[Phase.PreSale_1] = PhaseDetails(0.07 ether, 531_000_000 * 10**18, 0, 0, 0, false, false);
        phaseDetails[Phase.PreSale_2] = PhaseDetails(0.09 ether, 531_000_000 * 10**18, 0, 0, 0, false, false);
        phaseDetails[Phase.PublicSale] = PhaseDetails(0.12 ether, 265_000_000 * 10**18, 0, 0, 0, false, false);
    }

    function whitelistAddress(address _user) external onlyOwner {
        whitelisted[_user] = true;
        emit WhitelistUpdated(_user, true);
    }

    function removeWhitelistAddress(address _user) external onlyOwner {
        whitelisted[_user] = false;
        emit WhitelistUpdated(_user, false);
    }

    function buyTokens(uint256 usdtAmount, address referrer) external nonReentrant {
        require(currentPhase != Phase.NotStarted && currentPhase != Phase.Ended, "Sale not active");
        require(phaseDetails[currentPhase].isActive, "Phase is not active");
        require(block.timestamp >= phaseDetails[currentPhase].startTime, "Phase not started yet");
        require(block.timestamp <= phaseDetails[currentPhase].endTime, "Phase ended");
        require(usdtAmount >= 10 * 10**18, "Minimum purchase is 10 USDT");
        require(whitelisted[msg.sender], "Address not whitelisted");

        PhaseDetails storage phase = phaseDetails[currentPhase];
        uint256 tokensToBuy = (usdtAmount * 10**18) / phase.pricePerToken;
        require(tokensToBuy > 0, "Invalid amount");
        require(tokensToBuy <= phase.allocation, "Not enough tokens available");
        require(USDT_Token.allowance(msg.sender, address(this)) >= usdtAmount, "Insufficient USDT allowance");

        require(USDT_Token.transferFrom(msg.sender, address(this), usdtAmount), "USDT transfer failed");
        require(CSP.transfer(msg.sender, tokensToBuy), "CSP transfer failed");

        phase.allocation -= tokensToBuy;
        userBalances[msg.sender] += tokensToBuy;
        purchaseHistory[msg.sender] += tokensToBuy;
        unlockTime[msg.sender] = block.timestamp + phase.lockTime;

        if (referrer != address(0) && referrer != msg.sender) {
            uint256 referralReward = tokensToBuy / 10;
            require(CSP.transfer(referrer, referralReward), "Referral reward transfer failed");
            referrals[referrer] += referralReward;
            emit ReferralRewarded(referrer, msg.sender, referralReward);
        }

        emit TokensPurchased(msg.sender, usdtAmount, tokensToBuy);
    }

    function withdrawUSDT(uint256 _amount) external onlyOwner {
        require(_amount > 0, "Invalid amount");
        require(USDT_Token.balanceOf(address(this)) >= _amount, "Insufficient balance");
        require(USDT_Token.transfer(owner(), _amount), "USDT transfer failed");
        emit USDTWithdrawn(owner(), _amount);
    }

    function transfer(address recipient, uint256 amount) external {
        require(block.timestamp >= unlockTime[msg.sender], "Tokens are locked");
        require(userBalances[msg.sender] >= amount, "Insufficient balance");
        require(CSP.transfer(recipient, amount), "Transfer failed");

        userBalances[msg.sender] -= amount;
        userBalances[recipient] += amount;
        emit TokensTransferred(msg.sender, recipient, amount);
    }
}
