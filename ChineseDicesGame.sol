pragma solidity >=0.5.0 <0.6.0;

/**
 * @title SafeMath
 * @dev Math operations with safety checks that throw on error
 */
library SafeMath {
  function multiple(uint a, uint b) internal pure returns (uint) {
    uint c = a * b;
    assert(a == 0 || c / a == b);
    return c;
  }

  function div(uint a, uint b) internal pure returns (uint) {
    // assert(b > 0); // Solidity automatically throws when dividing by 0
    uint c = a / b;
    // assert(a == b * c + a % b); // There is no case in which this doesn't hold
    return c;
  }

  function sub(uint a, uint b) internal pure returns (uint) {
    assert(b <= a);
    return a - b;
  }

  function add(uint a, uint b) internal pure returns (uint) {
    uint c = a + b;
    assert(c >= a);
    return c;
  }
}

//contract ChineseDicesGame is usingProvable {
contract ChineseDicesGame {
    // Enums & Structs
    enum GameState { WaitForBid, GameProcessing, BidsEqualizing, BidsEqualized, WinnersMoneyTransferring, GameFinished }
    enum BidSides { BigNumber, SmallNumber }
    enum GameResult { Created, BigNumber, SmallNumber }

    // Contract structs
    struct Game {
        uint id;
        GameState state;
        GameResult result;
        uint totalDices;
        uint dice1;
        uint dice2;
        uint dice3;

        mapping(uint => PlayerBid) playerBids;
        uint currentPlayerBidIndex;
        uint bigNumberBidsAmount;
        uint smallNumberBidsAmount;
    }

    struct PlayerBid {
        uint id;
        address payable player;
        uint amount;
        BidSides bidSide;
        bool win;
    }

    // Contract owner
    address private owner;

    // Contract properties
    uint transactionFee; // in percent
    bool hasInProcessGame; // detect to prevent multiple games creation

    // Constants
    uint constant CUSTOM_API_CALL_GAS_LIMIT = 150000;
    uint constant AMOUNT_TO_PLAY = 0.001 ether;

    // Contacts game data
    mapping(uint => Game) public games;
    uint public currentGameIndex;

    // Set contract owner at the deployment time
    constructor() public payable {
        owner = msg.sender;
        currentGameIndex = 0;
        hasInProcessGame = false;
        transactionFee = 2;

        // Create new game
        createNewGame();
    }

    // Events
    event GameCreated(uint _gameId);
    event EqualizeBidSideRefundEvent(uint _playerId, uint _gameId, address _player, uint _refundAmount, BidSides _bidSide);
    event GameEqualizedEvent(uint _gameId, GameState _state, uint _bigNumberSideAmount, uint _smallNumberSideAmount);
    event GameProcessedEvent(uint _gameId, GameState _state, GameResult _result, uint _dice1, uint _dice2, uint _dice3, uint _totalDices);
    event PlayBidEvent(uint _id, uint _gameId, address _player, uint _amount, uint _fee, BidSides _bidSide);
    event WinnerTransferEvent(uint _gameId, uint _bidId, address _player, uint _amount);

    // Transactions

    /**
    * @dev Create new dices game and allow player to bid
    */
    function createNewGame() public onlyOwnerCanCall {
        require(hasInProcessGame == false, "There is a game now. Please to wait it be done.");
        currentGameIndex++;

        Game memory game = Game({
            id: currentGameIndex,
            bigNumberBidsAmount: 0,
            smallNumberBidsAmount: 0,
            currentPlayerBidIndex: 0,
            dice1: 0,
            dice2: 0,
            dice3: 0,
            totalDices: 0,
            state: GameState.WaitForBid,
            result: GameResult.Created
        });

        games[currentGameIndex] = game;
        emit GameCreated(currentGameIndex);
        hasInProcessGame = true;
    }

    /**
    * @dev Bid for a open game
    * @param _gameId The ID of game
    * @param _bidSide Choose dices side Big/Small number
    */
    function bidGame(uint _gameId, BidSides _bidSide)
        public payable returns (bool success, uint gameId, address bidAddress, uint realAmount) {
        // Find game to play
        Game storage game = games[_gameId];

        // Validate action and input data
        require(game.id != 0, "Can not find the game you want to bid.");
        require(game.state == GameState.WaitForBid, "This game is done. Please wait for the next game.");
        require(msg.value > AMOUNT_TO_PLAY, "Minimum amount to play is 0.001 ETH.");

        uint feeToPlay = msg.value * transactionFee / 100;
        uint realBidAmount = msg.value - feeToPlay;

        game.currentPlayerBidIndex++;

        PlayerBid memory newBid = PlayerBid({
            id: game.currentPlayerBidIndex,
            player: msg.sender,
            bidSide: _bidSide,
            amount: realBidAmount,
            win: false
        });

        game.playerBids[game.currentPlayerBidIndex] = newBid;

        if(_bidSide == BidSides.BigNumber){
            game.bigNumberBidsAmount += realBidAmount;
        } else {
            game.smallNumberBidsAmount += realBidAmount;
        }

        // Log event
        emit PlayBidEvent(game.currentPlayerBidIndex, _gameId, msg.sender, realBidAmount, feeToPlay, _bidSide);
        return(true, _gameId, msg.sender, realBidAmount);
    }

    /**
    * @dev Close game and process and transfer money to winners
    * After process is done. New game will be created anf opened for bidding
    * @param dice1 Dice 1 result
    * @param dice2 Dice 2 result
    * @param dice3 Dice 3 result
    */
    function processCurrentGame(uint dice1, uint dice2, uint dice3) external payable onlyOwnerCanCall {
        require(dice1 >= 1 && dice1 <= 6, "Invalid dice value for first result.");
        require(dice2 >= 1 && dice2 <= 6, "Invalid dice value for second result.");
        require(dice3 >= 1 && dice3 <= 6, "Invalid dice value for third result.");

        Game storage game = games[currentGameIndex];
        require(game.id != 0, "Invalid game to process.");
        require(game.state == GameState.BidsEqualized, "Invalid state to process.");

        game.state = GameState.GameProcessing;
        game.dice1 = dice1;
        game.dice2 = dice2;
        game.dice3 = dice3;
        uint totalDices = dice1 + dice2 + dice3;
        game.totalDices = totalDices;

        if(totalDices >= 3 && totalDices <= 10) {
            game.result = GameResult.SmallNumber;
        } else {
            game.result = GameResult.BigNumber;
        }

        // Validate constrains
        if(game.bigNumberBidsAmount == 0 || game.smallNumberBidsAmount == 0) {
            game.state = GameState.GameFinished;
            emit GameProcessedEvent(currentGameIndex, game.state, game.result, dice1, dice2, dice3, totalDices);

            hasInProcessGame = false;
            createNewGame();
            return;
        }

        game.state = GameState.WinnersMoneyTransferring;
        for(uint i = 1; i <= game.currentPlayerBidIndex; i ++) {
            PlayerBid memory bid = game.playerBids[i];

            if(game.result == GameResult.BigNumber && bid.bidSide == BidSides.BigNumber
                || game.result == GameResult.SmallNumber && bid.bidSide == BidSides.SmallNumber) {
                    // Winner receive money
                uint transferAmount = 2 * bid.amount;
                bid.player.transfer(transferAmount);
                game.playerBids[i].win = true;
            }
        }

        game.state = GameState.GameFinished;

        emit GameProcessedEvent(currentGameIndex, game.state, game.result, dice1, dice2, dice3, totalDices);
        // Create another game
        hasInProcessGame = false;
        createNewGame();
    }

    /***
    * @dev Equalize the total balance between BigNumber & SmallNumber
    * All difference amount will be refund to players
    */
    function equalizeBidSides() external payable onlyOwnerCanCall {
        Game storage game = games[currentGameIndex];
        // Validate action and input data
        require(game.id != 0, "Can not find the game you want to bid.");

        // Set state
        game.state = GameState.BidsEqualizing;

        if(game.bigNumberBidsAmount == 0 && game.smallNumberBidsAmount == 0) {
            game.state = GameState.BidsEqualized;
            return;
        }

        // Get small amount as base equalize amount
        bool equalizeBigNumberSide = game.bigNumberBidsAmount > game.smallNumberBidsAmount ? true : false;
        uint equalizeAmount = equalizeBigNumberSide ?
            game.bigNumberBidsAmount - game.smallNumberBidsAmount:
            game.smallNumberBidsAmount - game.bigNumberBidsAmount;

        if(equalizeBigNumberSide) {
            game.bigNumberBidsAmount = game.bigNumberBidsAmount - equalizeAmount;
        } else {
            game.smallNumberBidsAmount = game.smallNumberBidsAmount - equalizeAmount;
        }

        for(uint i = game.currentPlayerBidIndex; i >= 1; i --) {
            PlayerBid memory bid = game.playerBids[i];
            if(equalizeBigNumberSide == true && bid.bidSide == BidSides.SmallNumber
                || equalizeBigNumberSide == false && bid.bidSide == BidSides.BigNumber) {
                continue;
            }

            uint refundAmount = equalizeAmount > bid.amount ? bid.amount : equalizeAmount;
            equalizeAmount = equalizeAmount - refundAmount;

            if(address(this).balance > refundAmount && refundAmount > 0) {
                bid.player.transfer(refundAmount);
                game.playerBids[i].amount = bid.amount - refundAmount;
                emit EqualizeBidSideRefundEvent(bid.id, currentGameIndex, bid.player, refundAmount, bid.bidSide);
            }
        }

        game.state = GameState.BidsEqualized;
        emit GameEqualizedEvent(currentGameIndex, game.state, game.bigNumberBidsAmount, game.smallNumberBidsAmount);
    }

    /***
    * @dev Set transaction fee of contract
    * @param percent Percent of amount which player bid
    */
    function setTransactionFee(uint percent) external onlyOwnerCanCall {
        transactionFee = percent;
    }

    /**
    * @dev Get current open game
    * @return GameID, total big number bids amount and total small number bids amount
    */
    function getCurrentGame() public view
        returns (uint _gameId,
            GameState _state,
            GameResult _result,
            uint _dice1,
            uint _dice2,
            uint _dice3,
            uint _totalDices,
            uint _bigNumberBidsAmount,
            uint _smallNumberBidsAmount,
            uint _totalBids,
            uint[] memory _bids) {

        Game storage game = games[currentGameIndex];
        require(game.id != 0, "This game is not existed.");

        uint[] memory bids = new uint[](game.currentPlayerBidIndex);

        for(uint i = 0; i < game.currentPlayerBidIndex; i ++) {
            bids[i] = i + 1;
        }

        return (game.id,
            game.state,
            game.result,
            game.dice1,
            game.dice2,
            game.dice3,
            game.totalDices,
            game.bigNumberBidsAmount,
            game.smallNumberBidsAmount,
            game.currentPlayerBidIndex,
            bids);
    }

    /***
    * @dev Get current game index
    * @return Current game ID
    */
    function getCurrentGameId() public view returns (uint _id) {
        return currentGameIndex;
    }

    /**
    * @dev Get total games of contract
    * @return The total games
    */
    function getTotalGames() public view returns (uint totalGames) {
        return (currentGameIndex);
    }

    /**
    * @dev Get game detail information
    * @param gameId The ID of game to get information
    * @return GameID, total big number bids amount and total small number bids amount
    */
    function getGameInformation(uint gameId) public view
        returns (uint _gameId,
            GameState _state,
            GameResult _result,
            uint _dice1,
            uint _dice2,
            uint _dice3,
            uint _totalDices,
            uint _bigNumberBidsAmount,
            uint _smallNumberBidsAmount,
            uint _totalBids,
            uint[] memory _bids) {

        Game storage game = games[gameId];
        require(game.id != 0, "This game is not existed.");

        uint[] memory bids = new uint[](game.currentPlayerBidIndex);

        for(uint i = 0; i < game.currentPlayerBidIndex; i ++) {
            bids[i] = i + 1;
        }

        return (game.id,
            game.state,
            game.result,
            game.dice1,
            game.dice2,
            game.dice3,
            game.totalDices,
            game.bigNumberBidsAmount,
            game.smallNumberBidsAmount,
            game.currentPlayerBidIndex,
            bids);
    }

    /**
    * @dev Get game result with winners/losers
    * @param gameId Game ID
    */
    function getGameBids(uint gameId) public view
        returns (uint _gameId, uint[] memory _bids) {
        Game storage game = games[gameId];

        require(game.id != 0, "This game is not existed.");

        uint[] memory bids = new uint[](game.currentPlayerBidIndex);

        for(uint i = 0; i < game.currentPlayerBidIndex; i ++) {
            bids[i] = i + 1;
        }

        return (gameId, bids);
    }

    /***
    * @dev Get bid information
    * @param gameId Game ID
    * @param bidId Bid game ID
    */
    function getBidInformation(uint gameId, uint bidId) public view
        returns (uint _gameId, uint _bidId, bool _finished, address _player, uint _amount, bool _win, BidSides _bidSide) {

        Game storage game = games[gameId];
        require(game.id != 0, "This game is not existed.");
        bool finished = game.state == GameState.GameFinished ? true : false;

        PlayerBid memory playBid = game.playerBids[bidId];
        return (gameId,
            playBid.id,
            finished,
            playBid.player,
            playBid.amount,
            playBid.win,
            playBid.bidSide);
    }

    /**
    * @dev Transfer contract to the new owner
    * @param newOwner New owner address to transfer ownership
    */
    function transferOwner(address newOwner) external onlyOwnerCanCall {
        owner = newOwner;
    }

    /**
    * @dev Withdraw contract money
    * @param receiver Withdraw to address
    * @param amount Amount of money to withdraw
    */
    function withdraw(address payable receiver, uint amount) external payable onlyOwnerCanCall {
        require(address(this).balance > amount, "Invalid amount to withdraw.");
        receiver.transfer(amount);
    }

    function getContractBalance() public view returns (uint _balance) {
        return address(this).balance;
    }

    /**
    * @dev Validate accessing address is owner
    */
    modifier onlyOwnerCanCall {
        require (msg.sender == owner, "OnlyOwner methods called by non-owner.");
        _;
    }

    /**
    * @dev Validate accessing address is owner/request address.
    */
    //modifier onlyProvableCanCall() {
        //require (msg.sender == provable_cbAddress(), "OnlyOwner methods called by non-owner.");
        //_;
    //}
}