// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract StreamPay {
    address public immutable admin;
    uint256 public nextStreamId;
    uint256 public adminFeeBalance;

    uint256 public constant FEE_PERCENT = 1;

    struct Stream {
        address employer;
        address employee;
        uint256 companyId;
        uint256 totalDeposit;
        uint256 startTime;
        uint256 duration;
        uint256 totalWithdrawn;
        bool isClosed;
    }

    mapping(uint256 => Stream) public streams;

    event StreamCreated(
        uint256 indexed streamId,
        address indexed employer,
        address indexed employee,
        uint256 amount,
        uint256 duration
    );

    event FundsWithdrawn(
        uint256 indexed streamId,
        address indexed employee,
        uint256 employeeAmount,
        uint256 fee
    );

    event StreamCancelled(
        uint256 indexed streamId,
        address indexed cancelledBy,
        uint256 employeeAmount,
        uint256 employerRefund,
        uint256 fee
    );

    event AdminFeesClaimed(address indexed admin, uint256 amount);

    error InvalidAmount();
    error InvalidDuration();
    error InvalidEmployee();
    error StreamNotFound();
    error StreamAlreadyClosed();
    error NotAuthorized();
    error NothingToWithdraw();
    error TransferFailed();
    error NoFeesToClaim();

    constructor() {
        admin = msg.sender;
    }

    function createStream(
        address employee,
        uint256 companyId,
        uint256 duration
    ) external payable returns (uint256 streamId) {
        if (msg.value == 0) revert InvalidAmount();
        if (duration <= 15) revert InvalidDuration();
        if (employee == address(0)) revert InvalidEmployee();

        streamId = nextStreamId++;

        streams[streamId] = Stream({
            employer: msg.sender,
            employee: employee,
            companyId: companyId,
            totalDeposit: msg.value,
            startTime: block.timestamp,
            duration: duration,
            totalWithdrawn: 0,
            isClosed: false
        });

        emit StreamCreated(
            streamId,
            msg.sender,
            employee,
            msg.value,
            duration
        );
    }

    function getUnlockedAmount(uint256 streamId)
        public
        view
        returns (uint256)
    {
        Stream memory stream = streams[streamId];

        if (stream.totalDeposit == 0) return 0;

        uint256 endTime = stream.startTime + stream.duration;

        if (block.timestamp >= endTime) {
            return stream.totalDeposit;
        }

        uint256 elapsed = block.timestamp - stream.startTime;

        return (stream.totalDeposit * elapsed) / stream.duration;
    }

    function getClaimableAmount(uint256 streamId)
        public
        view
        returns (uint256)
    {
        Stream memory stream = streams[streamId];
        uint256 unlocked = getUnlockedAmount(streamId);

        if (unlocked <= stream.totalWithdrawn) return 0;

        return unlocked - stream.totalWithdrawn;
    }

    function withdraw(uint256 streamId) external {
        Stream storage stream = streams[streamId];

        if (stream.totalDeposit == 0) revert StreamNotFound();
        if (stream.isClosed) revert StreamAlreadyClosed();
        if (msg.sender != stream.employee) revert NotAuthorized();

        uint256 claimable = getClaimableAmount(streamId);
        if (claimable == 0) revert NothingToWithdraw();

        uint256 fee = (claimable * FEE_PERCENT) / 100;
        uint256 employeeAmount = claimable - fee;

        stream.totalWithdrawn += claimable;
        adminFeeBalance += fee;

        (bool success, ) = payable(stream.employee).call{value: employeeAmount}("");
        if (!success) revert TransferFailed();

        emit FundsWithdrawn(streamId, stream.employee, employeeAmount, fee);
    }

    function cancelStream(uint256 streamId) external {
        Stream storage stream = streams[streamId];

        if (stream.totalDeposit == 0) revert StreamNotFound();
        if (stream.isClosed) revert StreamAlreadyClosed();

        if (msg.sender != stream.employer && msg.sender != stream.employee) {
            revert NotAuthorized();
        }

        uint256 unlocked = getUnlockedAmount(streamId);
        uint256 vestedUnwithdrawn = 0;

        if (unlocked > stream.totalWithdrawn) {
            vestedUnwithdrawn = unlocked - stream.totalWithdrawn;
        }

        uint256 fee = (vestedUnwithdrawn * FEE_PERCENT) / 100;
        uint256 employeeAmount = vestedUnwithdrawn - fee;
        uint256 employerRefund = stream.totalDeposit - unlocked;

        stream.totalWithdrawn += vestedUnwithdrawn;
        stream.isClosed = true;
        adminFeeBalance += fee;

        if (employeeAmount > 0) {
            (bool employeeSuccess, ) =
                payable(stream.employee).call{value: employeeAmount}("");
            if (!employeeSuccess) revert TransferFailed();
        }

        if (employerRefund > 0) {
            (bool employerSuccess, ) =
                payable(stream.employer).call{value: employerRefund}("");
            if (!employerSuccess) revert TransferFailed();
        }

        emit StreamCancelled(
            streamId,
            msg.sender,
            employeeAmount,
            employerRefund,
            fee
        );
    }

    function claimAdminFees() external {
        if (msg.sender != admin) revert NotAuthorized();
        if (adminFeeBalance == 0) revert NoFeesToClaim();

        uint256 amount = adminFeeBalance;
        adminFeeBalance = 0;

        (bool success, ) = payable(admin).call{value: amount}("");
        if (!success) revert TransferFailed();

        emit AdminFeesClaimed(admin, amount);
    }

    function getStream(uint256 streamId)
        external
        view
        returns (Stream memory)
    {
        if (streams[streamId].totalDeposit == 0) {
            revert StreamNotFound();
        }

        return streams[streamId];
    }
}
