// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {StreamPay} from "../src/StreamPay.sol";

contract StreamPayTest is Test {
    StreamPay public streamPay;

    address public admin;
    address public employer;
    address public employee;
    address public stranger;

    uint256 constant DEPOSIT = 10 ether;
    uint256 constant DURATION = 100;

    function setUp() public {
        admin = makeAddr("admin");
        employer = makeAddr("employer");
        employee = makeAddr("employee");
        stranger = makeAddr("stranger");

        vm.deal(employer, 100 ether);
        vm.deal(employee, 100 ether);
        vm.deal(stranger, 100 ether);

        vm.prank(admin);
        streamPay = new StreamPay();
    }

    function _createDefaultStream() internal returns (uint256) {
        vm.prank(employer);

        return streamPay.createStream{value: DEPOSIT}(
            employee,
            1,
            DURATION
        );
    }

    function testAdminIsDeployer() public view {
        assertEq(streamPay.admin(), admin);
    }

    function testCreateStreamStoresCorrectData() public {
        uint256 streamId = _createDefaultStream();

        (
            address savedEmployer,
            address savedEmployee,
            uint256 companyId,
            uint256 totalDeposit,
            uint256 startTime,
            uint256 duration,
            uint256 totalWithdrawn,
            bool isClosed
        ) = streamPay.streams(streamId);

        assertEq(savedEmployer, employer);
        assertEq(savedEmployee, employee);
        assertEq(companyId, 1);
        assertEq(totalDeposit, DEPOSIT);
        assertGt(startTime, 0);
        assertEq(duration, DURATION);
        assertEq(totalWithdrawn, 0);
        assertFalse(isClosed);
    }

    function testCreateStreamRevertsWithZeroETH() public {
        vm.prank(employer);

        vm.expectRevert(StreamPay.InvalidAmount.selector);

        streamPay.createStream(employee, 1, DURATION);
    }

    function testCreateStreamRevertsWithShortDuration() public {
        vm.prank(employer);

        vm.expectRevert(StreamPay.InvalidDuration.selector);

        streamPay.createStream{value: DEPOSIT}(employee, 1, 15);
    }

    function testUnlockedAmountAfterHalfDuration() public {
        uint256 streamId = _createDefaultStream();

        vm.warp(block.timestamp + 50);

        uint256 unlocked = streamPay.getUnlockedAmount(streamId);

        assertEq(unlocked, 5 ether);
    }

    function testUnlockedAmountAfterFullDuration() public {
        uint256 streamId = _createDefaultStream();

        vm.warp(block.timestamp + DURATION + 1);

        uint256 unlocked = streamPay.getUnlockedAmount(streamId);

        assertEq(unlocked, DEPOSIT);
    }

    function testOnlyEmployeeCanWithdraw() public {
        uint256 streamId = _createDefaultStream();

        vm.warp(block.timestamp + 50);

        vm.prank(stranger);

        vm.expectRevert(StreamPay.NotAuthorized.selector);

        streamPay.withdraw(streamId);
    }

    function testEmployeeCanWithdrawVestedFundsAndFeeIsAdded() public {
        uint256 streamId = _createDefaultStream();

        vm.warp(block.timestamp + 50);

        uint256 employeeBalanceBefore = employee.balance;

        vm.prank(employee);
        streamPay.withdraw(streamId);

        uint256 expectedClaimable = 5 ether;
        uint256 expectedFee = (expectedClaimable * 1) / 100;
        uint256 expectedEmployeeAmount = expectedClaimable - expectedFee;

        assertEq(employee.balance, employeeBalanceBefore + expectedEmployeeAmount);
        assertEq(streamPay.adminFeeBalance(), expectedFee);

        (
            ,
            ,
            ,
            ,
            ,
            ,
            uint256 totalWithdrawn,
            
        ) = streamPay.streams(streamId);

        assertEq(totalWithdrawn, expectedClaimable);
    }

    function testCancelRefundsEmployerAndSettlesEmployee() public {
        uint256 streamId = _createDefaultStream();

        vm.warp(block.timestamp + 50);

        uint256 employeeBalanceBefore = employee.balance;
        uint256 employerBalanceBefore = employer.balance;

        vm.prank(employer);
        streamPay.cancelStream(streamId);

        uint256 vested = 5 ether;
        uint256 fee = (vested * 1) / 100;
        uint256 employeeExpected = vested - fee;
        uint256 employerExpectedRefund = 5 ether;

        assertEq(employee.balance, employeeBalanceBefore + employeeExpected);
        assertEq(employer.balance, employerBalanceBefore + employerExpectedRefund);
        assertEq(streamPay.adminFeeBalance(), fee);

        (
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            bool isClosed
        ) = streamPay.streams(streamId);

        assertTrue(isClosed);
    }

    function testAdminCanClaimFees() public {
        uint256 streamId = _createDefaultStream();

        vm.warp(block.timestamp + 50);

        vm.prank(employee);
        streamPay.withdraw(streamId);

        uint256 fee = (5 ether * 1) / 100;
        uint256 adminBalanceBefore = admin.balance;

        vm.prank(admin);
        streamPay.claimAdminFees();

        assertEq(admin.balance, adminBalanceBefore + fee);
        assertEq(streamPay.adminFeeBalance(), 0);
    }
}
