// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title Decentralized Escrow Service
 * @dev A trustless escrow system for secure peer-to-peer transactions
 */
contract Project {
    
    // Escrow states
    enum EscrowState {
        AWAITING_PAYMENT,
        AWAITING_DELIVERY,
        COMPLETE,
        DISPUTED,
        REFUNDED
    }
    
    // Escrow structure
    struct Escrow {
        address buyer;
        address seller;
        uint256 amount;
        EscrowState state;
        uint256 createdAt;
        uint256 timeoutDuration;
        string description;
        bool buyerApproved;
        bool sellerApproved;
    }
    
    // State variables
    mapping(uint256 => Escrow) public escrows;
    uint256 public escrowCounter;
    uint256 public constant DISPUTE_TIMEOUT = 7 days;
    
    // Events
    event EscrowCreated(uint256 indexed escrowId, address indexed buyer, address indexed seller, uint256 amount);
    event PaymentDeposited(uint256 indexed escrowId, uint256 amount);
    event DeliveryConfirmed(uint256 indexed escrowId);
    event PaymentReleased(uint256 indexed escrowId, address indexed seller, uint256 amount);
    event EscrowRefunded(uint256 indexed escrowId, address indexed buyer, uint256 amount);
    event DisputeRaised(uint256 indexed escrowId);
    
    // Modifiers
    modifier onlyBuyer(uint256 _escrowId) {
        require(msg.sender == escrows[_escrowId].buyer, "Only buyer can call this function");
        _;
    }
    
    modifier onlySeller(uint256 _escrowId) {
        require(msg.sender == escrows[_escrowId].seller, "Only seller can call this function");
        _;
    }
    
    modifier onlyParties(uint256 _escrowId) {
        require(
            msg.sender == escrows[_escrowId].buyer || msg.sender == escrows[_escrowId].seller,
            "Only buyer or seller can call this function"
        );
        _;
    }
    
    modifier validEscrow(uint256 _escrowId) {
        require(_escrowId < escrowCounter, "Invalid escrow ID");
        _;
    }
    
    /**
     * @dev Creates a new escrow agreement
     * @param _seller Address of the seller
     * @param _timeoutDuration Duration in seconds after which refund is possible
     * @param _description Description of the goods/services
     */
    function createEscrow(
        address _seller,
        uint256 _timeoutDuration,
        string memory _description
    ) external payable returns (uint256) {
        require(_seller != address(0), "Invalid seller address");
        require(_seller != msg.sender, "Buyer and seller cannot be the same");
        require(msg.value > 0, "Payment amount must be greater than 0");
        require(_timeoutDuration >= 1 hours, "Timeout duration must be at least 1 hour");
        
        uint256 escrowId = escrowCounter;
        
        escrows[escrowId] = Escrow({
            buyer: msg.sender,
            seller: _seller,
            amount: msg.value,
            state: EscrowState.AWAITING_DELIVERY,
            createdAt: block.timestamp,
            timeoutDuration: _timeoutDuration,
            description: _description,
            buyerApproved: false,
            sellerApproved: false
        });
        
        escrowCounter++;
        
        emit EscrowCreated(escrowId, msg.sender, _seller, msg.value);
        emit PaymentDeposited(escrowId, msg.value);
        
        return escrowId;
    }
    
    /**
     * @dev Confirms delivery and releases payment to seller
     * @param _escrowId The ID of the escrow
     */
    function confirmDelivery(uint256 _escrowId) 
        external 
        validEscrow(_escrowId) 
        onlyBuyer(_escrowId) 
    {
        Escrow storage escrow = escrows[_escrowId];
        require(escrow.state == EscrowState.AWAITING_DELIVERY, "Invalid escrow state");
        
        escrow.state = EscrowState.COMPLETE;
        escrow.buyerApproved = true;
        
        // Transfer payment to seller
        uint256 amount = escrow.amount;
        escrow.amount = 0;
        
        (bool success, ) = escrow.seller.call{value: amount}("");
        require(success, "Payment transfer failed");
        
        emit DeliveryConfirmed(_escrowId);
        emit PaymentReleased(_escrowId, escrow.seller, amount);
    }
    
    /**
     * @dev Handles refunds and disputes
     * @param _escrowId The ID of the escrow
     */
    function requestRefund(uint256 _escrowId) 
        external 
        validEscrow(_escrowId) 
        onlyBuyer(_escrowId) 
    {
        Escrow storage escrow = escrows[_escrowId];
        require(escrow.state == EscrowState.AWAITING_DELIVERY, "Invalid escrow state");
        
        // Check if timeout period has passed
        if (block.timestamp >= escrow.createdAt + escrow.timeoutDuration) {
            // Automatic refund after timeout
            escrow.state = EscrowState.REFUNDED;
            
            uint256 amount = escrow.amount;
            escrow.amount = 0;
            
            (bool success, ) = escrow.buyer.call{value: amount}("");
            require(success, "Refund transfer failed");
            
            emit EscrowRefunded(_escrowId, escrow.buyer, amount);
        } else {
            // Raise dispute if within timeout period
            escrow.state = EscrowState.DISPUTED;
            emit DisputeRaised(_escrowId);
        }
    }
    
    // View functions
    function getEscrowDetails(uint256 _escrowId) 
        external 
        view 
        validEscrow(_escrowId) 
        returns (
            address buyer,
            address seller,
            uint256 amount,
            EscrowState state,
            uint256 createdAt,
            uint256 timeoutDuration,
            string memory description
        ) 
    {
        Escrow storage escrow = escrows[_escrowId];
        return (
            escrow.buyer,
            escrow.seller,
            escrow.amount,
            escrow.state,
            escrow.createdAt,
            escrow.timeoutDuration,
            escrow.description
        );
    }
    
    function getEscrowState(uint256 _escrowId) 
        external 
        view 
        validEscrow(_escrowId) 
        returns (EscrowState) 
    {
        return escrows[_escrowId].state;
    }
    
    function getTotalEscrows() external view returns (uint256) {
        return escrowCounter;
    }
    
    // Emergency function to handle stuck funds (simplified dispute resolution)
    function resolveDispute(uint256 _escrowId, bool _favorBuyer) 
        external 
        validEscrow(_escrowId) 
        onlyParties(_escrowId) 
    {
        Escrow storage escrow = escrows[_escrowId];
        require(escrow.state == EscrowState.DISPUTED, "Escrow is not in disputed state");
        require(
            block.timestamp >= escrow.createdAt + DISPUTE_TIMEOUT,
            "Dispute timeout period has not passed"
        );
        
        uint256 amount = escrow.amount;
        escrow.amount = 0;
        
        if (_favorBuyer) {
            escrow.state = EscrowState.REFUNDED;
            (bool success, ) = escrow.buyer.call{value: amount}("");
            require(success, "Refund transfer failed");
            emit EscrowRefunded(_escrowId, escrow.buyer, amount);
        } else {
            escrow.state = EscrowState.COMPLETE;
            (bool success, ) = escrow.seller.call{value: amount}("");
            require(success, "Payment transfer failed");
            emit PaymentReleased(_escrowId, escrow.seller, amount);
        }
    }
}
