// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title NFReceipts
 * @notice Ancla recibos de Nightfall en L1 (Base Sepolia) para trazabilidad pública.
 * @dev Pensado para ser llamado por tu Orchestrator (relayer).
 */
contract NFReceipts is Ownable {
    struct Receipt {
        bool    exists;
        bytes32 commitmentHash;   // L2 commitment (NF)
        uint256 l2BlockNumber;    // L2 block
        bytes32 l1TxHash;         // L1 tx hash de escrow en contrato Nightfall
        uint64  anchoredAt;       // timestamp
        address caller;           // quién lo ancló (relayer)
    }

    // requestId → receipt
    mapping(bytes16 => Receipt) private _receipts;
    // relayer autorizado (tu Orchestrator)
    address public relayer;

    event RelayerUpdated(address indexed prev, address indexed next);
    event NFReceiptAnchored(
        bytes16 indexed requestId,
        bytes32 commitmentHash,
        uint256 l2BlockNumber,
        bytes32 l1TxHash,
        address indexed caller
    );

    error NotRelayer();
    error AlreadyAnchored();
    error UnknownReceipt();

    modifier onlyRelayer() {
        if (msg.sender != relayer) revert NotRelayer();
        _;
    }

    constructor(address initialOwner, address initialRelayer) Ownable(initialOwner) {
        relayer = initialRelayer;
        emit RelayerUpdated(address(0), initialRelayer);
    }

    function setRelayer(address next) external onlyOwner {
        emit RelayerUpdated(relayer, next);
        relayer = next;
    }

    /// @notice Ancla un recibo NF para un requestId (solo una vez).
    function anchorReceipt(
        bytes16 requestId,
        bytes32 commitmentHash,
        uint256 l2BlockNumber,
        bytes32 l1TxHash
    ) external onlyRelayer {
        if (_receipts[requestId].exists) revert AlreadyAnchored();

        _receipts[requestId] = Receipt({
            exists: true,
            commitmentHash: commitmentHash,
            l2BlockNumber: l2BlockNumber,
            l1TxHash: l1TxHash,
            anchoredAt: uint64(block.timestamp),
            caller: msg.sender
        });

        emit NFReceiptAnchored(requestId, commitmentHash, l2BlockNumber, l1TxHash, msg.sender);
    }

    // -------- Getters --------

    function getReceipt(bytes16 requestId)
        external
        view
        returns (
            bool exists,
            bytes32 commitmentHash,
            uint256 l2BlockNumber,
            bytes32 l1TxHash,
            uint64 anchoredAt,
            address caller
        )
    {
        Receipt memory r = _receipts[requestId];
        if (!r.exists) revert UnknownReceipt();
        return (r.exists, r.commitmentHash, r.l2BlockNumber, r.l1TxHash, r.anchoredAt, r.caller);
    }

    function isAnchored(bytes16 requestId) external view returns (bool) {
        return _receipts[requestId].exists;
    }
}
