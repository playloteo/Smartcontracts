import "zeppelin/contracts/math/SafeMath.sol";
import "zeppelin/contracts/token/ERC20/ERC20Basic.sol";
import "zeppelin/contracts/token/ERC20/ERC20.sol";
import "zeppelin/contracts/token/ERC20/BasicToken.sol";
import "zeppelin/contracts/token/ERC20/StandardToken.sol";
import "zeppelin/contracts/token/ERC827/ERC827.sol";
import "zeppelin/contracts/token/ERC827/ERC827Token.sol";
import "zeppelin/contracts/ownership/Ownable.sol";
import "./Recoverable.sol";
import "./StandardTokenExt.sol";
import "./oraclizeAPI_0.4.sol";


contract LoteoGame is Recoverable, usingOraclize {
  using SafeMath for uint256;

  StandardTokenExt public ticketToken;
  StandardTokenExt public bonusToken;
  uint256 public interval;
  uint256 public firstGameTime;
  address public ticketVault;
  address public bonusVault;
  address public serviceVault;
  address public feeVault;

  struct  Game {
    uint256 endTime;
    mapping(uint256 => address) tickets;
    uint256 ticketsBought;
    uint256 ticketsUsed;
    address winner;
    uint256 prize;
    uint256 seed;
    mapping(address => uint256) ticketsByUser;
  }

  mapping(uint256 => Game) public games;
  uint256 public gameIndex;
  uint256 public maxOneTimeBuy = 100;
  uint256 public silencePeriod = 1800;
  uint256 public ticketCostInWei = 10000000000000000;
  uint256 public feesInWei = 0;
  string private apiKey = "1aed91d9";

  event GameResolved(string result, address winner, uint256 prize);

  mapping (address => bool) public priceAgents;

  modifier onlyPriceAgent() {
    if(!priceAgents[msg.sender]) {
      revert();
    }
    _;
  }

  function setPriceAgent(address addr, bool state) onlyOwner public {
    priceAgents[addr] = state;
  }

  function LoteoGame(address _ticketToken, address _bonusToken, uint256 _interval, uint256 _firstGameTime, uint256 _seed) {
    if (now > _firstGameTime) revert();
    ticketToken = StandardTokenExt(_ticketToken);
    bonusToken = StandardTokenExt(_bonusToken);
    interval = _interval;
    firstGameTime = _firstGameTime;
    gameIndex = 0;
    games[gameIndex].endTime = firstGameTime;
    games[gameIndex].seed = _seed;
  }

  function() payable public {
  }

  function PRIZE_POOL() public view returns (string) {
    uint256 prizeInWei = games[gameIndex].ticketsBought.mul(ticketCostInWei);
    uint256 whole = prizeInWei.div(1 ether);
    uint256 fraction = prizeInWei.div(1 finney) - (whole.mul(1000));
    string memory fractionString = uint2str(fraction);
    if (fraction < 10) {
      fractionString = strConcat('00', fractionString);
    } else if (fraction < 100) {
      fractionString = strConcat('0', fractionString);
    }
    return strConcat(uint2str(whole), '.', fractionString);
  }

  function LOTEU() public view returns (uint256) {
    return (games[gameIndex].ticketsUsed.sub(games[gameIndex].ticketsBought).mul(100));
  }

  function LOTEU_total() public view returns (uint256) {
    return bonusToken.balanceOf(bonusVault);
  }

  function blockchain_FEES() public view returns (string) {
    uint256 whole = feesInWei.div(1 ether);
    uint256 fraction = feesInWei.div(1 finney) - (whole.mul(1000));
    string memory fractionString = uint2str(fraction);
    if (fraction < 10) {
      fractionString = strConcat('00', fractionString);
    } else if (fraction < 100) {
      fractionString = strConcat('0', fractionString);
    }
    return strConcat(uint2str(whole), '.', fractionString);
  }

  function setTicketVault(address vault) public onlyOwner {
    ticketVault = vault;
  }

  function setBonusVault(address vault) public onlyOwner {
    bonusVault = vault;
  }

  function setServiceVault(address vault) public onlyOwner {
    serviceVault = vault;
  }

  function setFeeVault(address vault) public onlyOwner {
    feeVault = vault;
  }

  function setVaults(address _ticketVault, address _bonusVault, address _serviceVault, address _feeVault) public onlyOwner {
    ticketVault = _ticketVault;
    bonusVault = _bonusVault;
    serviceVault = _serviceVault;
    feeVault = _feeVault;
  }

  function setApiKey(string _apiKey) public onlyOwner {
    apiKey = _apiKey;
  }

  function setPrice(uint256 price) public onlyPriceAgent {
    ticketCostInWei = price;
  }

  function setFees(uint fees) public onlyPriceAgent {
    feesInWei = fees;
  }

  function getTicketsForUser(address user) public view returns (uint256) {
    return games[gameIndex].ticketsByUser[user];
  }

  function useTickets(uint256 amount, bool bonusTicketsUsed) public {
    if (amount > maxOneTimeBuy) revert();
    if (now > games[gameIndex].endTime.sub(silencePeriod)) revert();
    ticketToken.transferFrom(msg.sender, ticketVault, amount);
    if (bonusTicketsUsed) {
      bonusToken.transferFrom(msg.sender, ticketVault, amount.mul(10000000000));
    }
    games[gameIndex].ticketsBought = games[gameIndex].ticketsBought.add(amount);
    uint256 amountToUse = amount;
    if (bonusTicketsUsed) {
      amountToUse = amountToUse.mul(2);
    }
    uint256 position = games[gameIndex].ticketsUsed;
    for (uint256 i = 0; i < amountToUse; i++) {
      games[gameIndex].tickets[position] = msg.sender;
      position++;
    }
    games[gameIndex].ticketsUsed = games[gameIndex].ticketsUsed.add(amountToUse);
    games[gameIndex].ticketsByUser[msg.sender] = games[gameIndex].ticketsByUser[msg.sender].add(amountToUse);
  }

  function useTicketsForUser(address user, uint256 amount, bool bonusTicketsUsed) public onlyPriceAgent {
    if (amount > maxOneTimeBuy) revert();
    if (now > games[gameIndex].endTime.sub(silencePeriod)) revert();
    ticketToken.transferFrom(user, ticketVault, amount);
    if (bonusTicketsUsed) {
      bonusToken.transferFrom(user, ticketVault, amount.mul(10000000000));
    }
    games[gameIndex].ticketsBought = games[gameIndex].ticketsBought.add(amount);
    uint256 amountToUse = amount;
    if (bonusTicketsUsed) {
      amountToUse = amountToUse.mul(2);
    }
    uint256 position = games[gameIndex].ticketsUsed;
    for (uint256 i = 0; i < amountToUse; i++) {
      games[gameIndex].tickets[position] = user;
      position++;
    }
    games[gameIndex].ticketsUsed = games[gameIndex].ticketsUsed.add(amountToUse);
    games[gameIndex].ticketsByUser[user] = games[gameIndex].ticketsByUser[user].add(amountToUse);
  }

  function __callback(bytes32 myid, string result) {
    if (now < games[gameIndex].endTime) revert();
    if (msg.sender != oraclize_cbAddress()) revert();
    uint256 random = parseInt(result);
    random = (games[gameIndex].seed.add(random)) % games[gameIndex].ticketsUsed;
    if (random >= games[gameIndex].ticketsUsed) revert();
    address winner = games[gameIndex].tickets[random];
    games[gameIndex].winner = winner;
    gameIndex++;
    games[gameIndex].seed = random;
    games[gameIndex].endTime = games[gameIndex - 1].endTime.add(interval);
    uint256 totalBank = ticketCostInWei.mul(games[gameIndex - 1].ticketsBought).sub(feesInWei);
    uint256 prize = totalBank.div(100).mul(75);
    uint256 service = prize.div(3);
    games[gameIndex - 1].prize = prize;
    GameResolved(result, winner, prize);
    if (!feeVault.send(feesInWei)) revert();
    if (!winner.send(prize)) revert();
    if (!serviceVault.send(service)) revert();
  }

  function resolveGame() public {
    if (now < games[gameIndex].endTime) revert();
    if (games[gameIndex].ticketsUsed > 0) {
      oraclize_query("URL", strConcat('json(https://playloteo.com/api/random-number?secret=', apiKey, '&min=0&max=', uint2str(uint(games[gameIndex].ticketsUsed) - 1), ').randomNumber'), 1000000);
    } else {
      gameIndex++;
      games[gameIndex].seed = games[gameIndex - 1].seed;
      games[gameIndex].endTime = games[gameIndex - 1].endTime.add(interval);
    }
  }

}
