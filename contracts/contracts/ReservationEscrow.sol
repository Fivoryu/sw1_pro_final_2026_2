// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @notice Local-only escrow for fixed COP-denominated test-token reservation deposits.
contract ReservationEscrow is EIP712, ReentrancyGuard {
    using SafeERC20 for IERC20;

    enum Action {
        Deposit,
        Accept,
        Reject,
        Cancel
    }

    enum Status {
        None,
        Pending,
        Accepted,
        Rejected,
        Cancelled,
        Expired
    }

    struct ReservationAction {
        bytes32 reservationId;
        bytes32 listingId;
        address customer;
        address agency;
        address actor;
        uint8 action;
        uint256 amount;
        uint64 deadline;
        uint256 nonce;
    }

    struct Reservation {
        bytes32 listingId;
        address customer;
        address agency;
        uint256 amount;
        uint64 deadline;
        Status status;
        uint256 depositedAmount;
    }

    bytes32 private constant _ACTION_TYPEHASH = keccak256(
        "ReservationAction(bytes32 reservationId,bytes32 listingId,address customer,address agency,address actor,uint8 action,uint256 amount,uint64 deadline,uint256 nonce)"
    );

    error InvalidAddress();
    error InvalidTokenConfiguration();
    error InexactTokenTransfer();
    error InvalidAction();
    error UnauthorizedActor();
    error InvalidSigner();
    error InvalidNonce();
    error DeadlinePassed();
    error ReservationMismatch();
    error ReservationNotPending();
    error DepositAlreadyMade();
    error InvalidDepositAmount();
    error DepositRequired();
    error NotExpirable();

    event Deposited(
        bytes32 indexed reservationId,
        bytes32 indexed listingId,
        address indexed customer,
        uint256 amount,
        uint256 nonce
    );
    event Accepted(
        bytes32 indexed reservationId,
        bytes32 indexed listingId,
        address indexed agency,
        uint256 amount,
        uint256 nonce
    );
    event Rejected(
        bytes32 indexed reservationId,
        bytes32 indexed listingId,
        address indexed customer,
        uint256 refundAmount,
        uint256 nonce
    );
    event Cancelled(
        bytes32 indexed reservationId,
        bytes32 indexed listingId,
        address indexed actor,
        uint256 refundAmount,
        uint256 nonce
    );
    event Expired(
        bytes32 indexed reservationId,
        bytes32 indexed listingId,
        address indexed customer,
        uint256 refundAmount,
        uint256 nonce
    );

    IERC20 public immutable token;
    address public immutable authorizedSigner;
    mapping(bytes32 reservationId => uint256 nonce) public nonces;
    mapping(bytes32 reservationId => Reservation data) private _reservations;

    constructor(address tokenAddress, address signerAddress)
        EIP712("RoomForgeReservationEscrow", "1")
    {
        if (tokenAddress == address(0) || tokenAddress.code.length == 0 || signerAddress == address(0)) {
            revert InvalidAddress();
        }
        try IERC20Metadata(tokenAddress).decimals() returns (uint8 tokenDecimals) {
            if (tokenDecimals != 2) revert InvalidTokenConfiguration();
        } catch {
            revert InvalidTokenConfiguration();
        }
        token = IERC20(tokenAddress);
        authorizedSigner = signerAddress;
    }

    function reservation(bytes32 reservationId) external view returns (Reservation memory) {
        return _reservations[reservationId];
    }

    function deposit(ReservationAction calldata action, bytes calldata signature) external nonReentrant {
        _authorize(action, signature, Action.Deposit);
        if (action.amount == 0) revert InvalidDepositAmount();

        Reservation storage reservationData = _prepare(action);
        if (reservationData.status != Status.Pending) revert ReservationNotPending();
        if (reservationData.depositedAmount != 0) revert DepositAlreadyMade();

        reservationData.depositedAmount = action.amount;
        nonces[action.reservationId] = action.nonce + 1;
        _transferExactIn(action.customer, action.amount);

        emit Deposited(action.reservationId, action.listingId, action.customer, action.amount, action.nonce);
    }

    function accept(ReservationAction calldata action, bytes calldata signature) external nonReentrant {
        _authorize(action, signature, Action.Accept);
        Reservation storage reservationData = _prepare(action);
        if (reservationData.status != Status.Pending) revert ReservationNotPending();
        _requireDepositIfConfigured(reservationData);

        uint256 payout = reservationData.depositedAmount;
        reservationData.depositedAmount = 0;
        reservationData.status = Status.Accepted;
        nonces[action.reservationId] = action.nonce + 1;
        if (payout != 0) _transferExactOut(reservationData.agency, payout);

        emit Accepted(action.reservationId, action.listingId, reservationData.agency, payout, action.nonce);
    }

    function reject(ReservationAction calldata action, bytes calldata signature) external nonReentrant {
        _authorize(action, signature, Action.Reject);
        Reservation storage reservationData = _prepare(action);
        if (reservationData.status != Status.Pending) revert ReservationNotPending();
        _requireDepositIfConfigured(reservationData);

        uint256 refundAmount = reservationData.depositedAmount;
        reservationData.depositedAmount = 0;
        reservationData.status = Status.Rejected;
        nonces[action.reservationId] = action.nonce + 1;
        if (refundAmount != 0) _transferExactOut(reservationData.customer, refundAmount);

        emit Rejected(action.reservationId, action.listingId, reservationData.customer, refundAmount, action.nonce);
    }

    function cancel(ReservationAction calldata action, bytes calldata signature) external nonReentrant {
        _authorize(action, signature, Action.Cancel);
        Reservation storage reservationData = _prepare(action);
        if (reservationData.status != Status.Pending) revert ReservationNotPending();
        if (reservationData.depositedAmount != 0 && reservationData.depositedAmount != reservationData.amount) {
            revert ReservationMismatch();
        }

        uint256 refundAmount = reservationData.depositedAmount;
        reservationData.depositedAmount = 0;
        reservationData.status = Status.Cancelled;
        nonces[action.reservationId] = action.nonce + 1;
        if (refundAmount != 0) _transferExactOut(reservationData.customer, refundAmount);

        emit Cancelled(action.reservationId, action.listingId, action.actor, refundAmount, action.nonce);
    }

    /// @notice Permissionlessly refunds a deposited pending reservation at or after its deadline.
    function expire(bytes32 reservationId) external nonReentrant {
        Reservation storage reservationData = _reservations[reservationId];
        if (reservationData.status != Status.Pending) revert ReservationNotPending();
        if (block.timestamp < reservationData.deadline || reservationData.depositedAmount == 0) {
            revert NotExpirable();
        }

        uint256 refundAmount = reservationData.depositedAmount;
        uint256 actionNonce = nonces[reservationId];
        reservationData.depositedAmount = 0;
        reservationData.status = Status.Expired;
        nonces[reservationId] = actionNonce + 1;
        _transferExactOut(reservationData.customer, refundAmount);

        emit Expired(
            reservationId,
            reservationData.listingId,
            reservationData.customer,
            refundAmount,
            actionNonce
        );
    }

    function _authorize(
        ReservationAction calldata action,
        bytes calldata signature,
        Action expectedAction
    ) private view {
        if (action.action != uint8(expectedAction)) revert InvalidAction();
        if (
            action.reservationId == bytes32(0) || action.listingId == bytes32(0) ||
            action.customer == address(0) || action.agency == address(0) || action.actor == address(0)
        ) revert InvalidAddress();
        if (msg.sender != action.actor) revert UnauthorizedActor();

        if (expectedAction == Action.Deposit && action.actor != action.customer) revert UnauthorizedActor();
        if (
            (expectedAction == Action.Accept || expectedAction == Action.Reject) &&
            action.actor != action.agency
        ) revert UnauthorizedActor();
        if (
            expectedAction == Action.Cancel &&
            action.actor != action.customer && action.actor != action.agency
        ) revert UnauthorizedActor();

        if (action.nonce != nonces[action.reservationId]) revert InvalidNonce();
        if (block.timestamp >= action.deadline) revert DeadlinePassed();

        bytes32 structHash = keccak256(
            abi.encode(
                _ACTION_TYPEHASH,
                action.reservationId,
                action.listingId,
                action.customer,
                action.agency,
                action.actor,
                action.action,
                action.amount,
                action.deadline,
                action.nonce
            )
        );
        (address recovered, ECDSA.RecoverError error,) = ECDSA.tryRecover(
            _hashTypedDataV4(structHash),
            signature
        );
        if (error != ECDSA.RecoverError.NoError || recovered != authorizedSigner) revert InvalidSigner();
    }

    function _prepare(ReservationAction calldata action) private returns (Reservation storage reservationData) {
        reservationData = _reservations[action.reservationId];
        if (reservationData.status == Status.None) {
            reservationData.listingId = action.listingId;
            reservationData.customer = action.customer;
            reservationData.agency = action.agency;
            reservationData.amount = action.amount;
            reservationData.deadline = action.deadline;
            reservationData.status = Status.Pending;
            return reservationData;
        }

        if (
            reservationData.listingId != action.listingId ||
            reservationData.customer != action.customer ||
            reservationData.agency != action.agency ||
            reservationData.amount != action.amount ||
            reservationData.deadline != action.deadline
        ) revert ReservationMismatch();
    }

    function _requireDepositIfConfigured(Reservation storage reservationData) private view {
        if (reservationData.amount != 0 && reservationData.depositedAmount != reservationData.amount) {
            revert DepositRequired();
        }
    }

    function _transferExactIn(address from, uint256 amount) private {
        uint256 balanceBefore = token.balanceOf(address(this));
        token.safeTransferFrom(from, address(this), amount);
        uint256 balanceAfter = token.balanceOf(address(this));
        if (balanceAfter < balanceBefore || balanceAfter - balanceBefore != amount) {
            revert InexactTokenTransfer();
        }
    }

    function _transferExactOut(address recipient, uint256 amount) private {
        uint256 escrowBefore = token.balanceOf(address(this));
        uint256 recipientBefore = token.balanceOf(recipient);
        token.safeTransfer(recipient, amount);
        uint256 escrowAfter = token.balanceOf(address(this));
        uint256 recipientAfter = token.balanceOf(recipient);
        if (
            escrowAfter > escrowBefore || escrowBefore - escrowAfter != amount ||
            recipientAfter < recipientBefore || recipientAfter - recipientBefore != amount
        ) revert InexactTokenTransfer();
    }
}
