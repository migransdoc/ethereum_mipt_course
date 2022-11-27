// SPDX-License-Identifier: MIT
pragma solidity ^0.8.8;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";

error Staker__TimeForStakingHasEnded();

contract Staker {
    event Staking(address indexed staker, uint256 amount);
    event Withdraw(address indexed withdrawer, uint256 amount);

    address private s_owner;
    ExampleExternalContract private s_ExampleExternalContract;
    BronzeTier public s_bronzeTier;
    SilverTier public s_SilverTier;
    GoldTier public s_GoldTier;

    uint256[3] public tiers; // required amount of money for getting tier (bronze, silver, gold)
    uint256 public immutable i_end; // timestamp of staking end
    bool public s_isStakingEnd = false;
    bool public s_isEnoughMoneyStaked = false;
    uint256 public s_moneyCollected = 0;
    uint256 public s_treshhold;
    mapping(address => uint256) private s_balances;

    modifier onlyOwner() {
        require(msg.sender == s_owner);
        _;
    }

    constructor(
        uint256 _treshhold,
        uint256 _bronzeTier,
        uint256 _silverTier,
        uint256 _goldTier
    ) {
        i_end = block.timestamp + 2 days;
        s_treshhold = _treshhold;
        tiers[0] = _bronzeTier;
        tiers[1] = _silverTier;
        tiers[2] = _goldTier;
        s_owner = msg.sender;
    }

    function pay() public payable {
        require(!s_isStakingEnd && !s_isEnoughMoneyStaked);
        if (block.timestamp > i_end) {
            complete();
            revert Staker__TimeForStakingHasEnded();
        }
        s_balances[msg.sender] += msg.value;
        s_moneyCollected += msg.value;
        emit Staking(msg.sender, msg.value);
    }

    function complete() internal {
        s_isStakingEnd = true;
        s_isEnoughMoneyStaked = (s_moneyCollected > s_treshhold ? true : false);
        if (s_isEnoughMoneyStaked) {
            (bool success, ) = address(s_ExampleExternalContract).call{value: s_moneyCollected}("");
            require(success);
        }
    }

    function withdraw() public {
        require(!s_isEnoughMoneyStaked && !s_isStakingEnd);
        require(s_balances[msg.sender] > 0);
        uint256 value = s_balances[msg.sender];
        s_balances[msg.sender] = 0;
        (bool success, ) = payable(msg.sender).call{value: value}("");
        require(success);
        emit Withdraw(msg.sender, value);
    }

    function sendNft() public {
        require(s_isEnoughMoneyStaked && s_isStakingEnd);
        require(s_balances[msg.sender] > 0);
        if (s_balances[msg.sender] >= tiers[0] && s_balances[msg.sender] < tiers[1]) {
            s_bronzeTier.mintNft(msg.sender);
        } else if (s_balances[msg.sender] < tiers[2]) {
            s_SilverTier.mintNft(msg.sender);
        } else if (s_balances[msg.sender] >= tiers[2]) {
            s_GoldTier.mintNft(msg.sender);
        }
    }

    function getBalanceOfStaker(address staker) public view returns (uint256) {
        return s_balances[staker];
    }

    function setExampleExternalContractAddress(address _ExampleExternalContractAddress)
        public
        onlyOwner
    {
        s_ExampleExternalContract = ExampleExternalContract(
            payable(_ExampleExternalContractAddress)
        );
    }

    function setTierAddress(
        address _bronzeTierAddress,
        address _silverTierAddress,
        address _goldTierAddress
    ) public onlyOwner {
        s_bronzeTier = BronzeTier(_bronzeTierAddress);
        s_SilverTier = SilverTier(_silverTierAddress);
        s_GoldTier = GoldTier(_goldTierAddress);
    }
}

contract ExampleExternalContract {
    receive() external payable {}

    fallback() external payable {}

    function getBalance() public view returns (uint256) {
        return address(this).balance;
    }
}

contract BronzeTier is ERC721 {
    string public constant TOKEN_URI =
        "ipfs://bafybeig37ioir76s7mg5oobetncojcm3c3hxasyd4rvid4jqhy4gkaheg4/?filename=0-PUG.json";
    uint256 private s_tokenCounter;

    constructor() ERC721("Bronze NFT", "BNFT") {
        s_tokenCounter = 0;
    }

    function mintNft(address _staker) public {
        s_tokenCounter += 1;
        _safeMint(_staker, s_tokenCounter);
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        return TOKEN_URI;
    }

    function getTokenCounter() public view returns (uint256) {
        return s_tokenCounter;
    }
}

contract SilverTier is ERC721 {
    string public constant TOKEN_URI =
        "ipfs://bafybeig37ioir76s7mg5oobetncojcm3c3hxasyd4rvid4jqhy4gkaheg4/?filename=0-PUG.json";
    uint256 private s_tokenCounter;

    constructor() ERC721("Silver NFT", "SNFT") {
        s_tokenCounter = 0;
    }

    function mintNft(address _staker) public {
        s_tokenCounter += 1;
        _safeMint(_staker, s_tokenCounter);
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        return TOKEN_URI;
    }

    function getTokenCounter() public view returns (uint256) {
        return s_tokenCounter;
    }
}

contract GoldTier is ERC721 {
    string public constant TOKEN_URI =
        "ipfs://bafybeig37ioir76s7mg5oobetncojcm3c3hxasyd4rvid4jqhy4gkaheg4/?filename=0-PUG.json";
    uint256 private s_tokenCounter;

    constructor() ERC721("Gold NFT", "GNFT") {
        s_tokenCounter = 0;
    }

    function mintNft(address _staker) public {
        s_tokenCounter += 1;
        _safeMint(_staker, s_tokenCounter);
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        return TOKEN_URI;
    }

    function getTokenCounter() public view returns (uint256) {
        return s_tokenCounter;
    }
}
