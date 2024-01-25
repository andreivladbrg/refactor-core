// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.22;

import { UD60x18, ud } from "@prb/math/src/UD60x18.sol";

import { Lockup, LockupDynamic } from "../types/DataTypes.sol";
import { Errors } from "./Errors.sol";

/// @title Helpers
/// @notice Library with helper functions needed across the Sablier V2 contracts.
library Helpers {
    /*//////////////////////////////////////////////////////////////////////////
                             INTERNAL CONSTANT FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Checks that neither fee is greater than `maxFee`, and then calculates the protocol fee amount, the
    /// broker fee amount, and the deposit amount from the total amount.
    function checkAndCalculateFees(
        uint128 totalAmount,
        UD60x18 protocolFee,
        UD60x18 brokerFee,
        UD60x18 maxFee
    )
        internal
        pure
        returns (Lockup.CreateAmounts memory amounts)
    {
        // When the total amount is zero, the fees are also zero.
        if (totalAmount == 0) {
            return Lockup.CreateAmounts(0, 0, 0);
        }

        // Checks: the protocol fee is not greater than `maxFee`.
        if (protocolFee.gt(maxFee)) {
            revert Errors.SablierV2Lockup_ProtocolFeeTooHigh(protocolFee, maxFee);
        }
        // Checks: the broker fee is not greater than `maxFee`.
        if (brokerFee.gt(maxFee)) {
            revert Errors.SablierV2Lockup_BrokerFeeTooHigh(brokerFee, maxFee);
        }

        // Calculate the protocol fee amount.
        // The cast to uint128 is safe because the maximum fee is hard coded.
        amounts.protocolFee = uint128(ud(totalAmount).mul(protocolFee).intoUint256());

        // Calculate the broker fee amount.
        // The cast to uint128 is safe because the maximum fee is hard coded.
        amounts.brokerFee = uint128(ud(totalAmount).mul(brokerFee).intoUint256());

        // Assert that the total amount is strictly greater than the sum of the protocol fee amount and the
        // broker fee amount.
        assert(totalAmount > amounts.protocolFee + amounts.brokerFee);

        // Calculate the deposit amount (the amount to stream, net of fees).
        amounts.deposit = totalAmount - amounts.protocolFee - amounts.brokerFee;

        if (amounts.deposit == 0) {
            revert Errors.SablierV2Lockup_DepositAmountZero();
        }
    }

    /// @dev Checks that the segment array counts match, and then adjusts the segments by calculating the timestampts.
    function checkDurationsAndCalculateTimestamps(LockupDynamic.SegmentWithDuration[] memory segments)
        internal
        view
        returns (LockupDynamic.Segment[] memory segmentsWithTimestamps)
    {
        uint256 segmentCount = segments.length;
        segmentsWithTimestamps = new LockupDynamic.Segment[](segmentCount);

        // Make the current time the stream's start time.
        uint40 startTime = uint40(block.timestamp);

        // It is safe to use unchecked arithmetic because {_createWithTimestamp} will nonetheless check the soundness
        // of the calculated segment timestampts.
        unchecked {
            // Precompute the first segment because of the need to add the start time to the first segment duration.
            segmentsWithTimestamps[0] = LockupDynamic.Segment({
                amount: segments[0].amount,
                exponent: segments[0].exponent,
                timestampt: startTime + segments[0].duration
            });

            // Copy the segment amounts and exponents, and calculate the segment timestampts.
            for (uint256 i = 1; i < segmentCount; ++i) {
                segmentsWithTimestamps[i] = LockupDynamic.Segment({
                    amount: segments[i].amount,
                    exponent: segments[i].exponent,
                    timestampt: segmentsWithTimestamps[i - 1].timestampt + segments[i].duration
                });
            }
        }
    }

    /*//////////////////////////////////////////////////////////////////////////
                             PRIVATE CONSTANT FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Checks that:
    ///
    /// 1. The first timestampt is strictly greater than the start time.
    /// 2. The timestampts are ordered chronologically.
    /// 3. There are no duplicate timestampts.
    /// 4. The deposit amount is equal to the sum of all segment amounts.
    function checkSegments(
        LockupDynamic.Segment[] memory segments,
        uint128 depositAmount,
        uint40 startTime,
        uint256 maxSegmentCount
    )
        internal
        pure
        returns (uint40)
    {
        // Checks: the segment count is not zero.
        uint256 segmentCount = segments.length;
        if (segmentCount == 0) {
            revert Errors.SablierV2LockupDynamic_SegmentCountZero();
        }

        // Checks: the segment count is not greater than the maximum allowed.
        if (segmentCount > maxSegmentCount) {
            revert Errors.SablierV2LockupDynamic_SegmentCountTooHigh(segmentCount);
        }

        // Checks: the start time is strictly less than the first segment timestampt.
        if (startTime >= segments[0].timestampt) {
            revert Errors.SablierV2LockupDynamic_StartTimeNotLessThanFirstSegmentTimestamp(
                startTime, segments[0].timestampt
            );
        }

        // Pre-declare the variables needed in the for loop.
        uint128 segmentAmountsSum;
        uint40 currentTimestamp;
        uint40 previousTimestamp;

        // Iterate over the segments to:
        //
        // 1. Calculate the sum of all segment amounts.
        // 2. Check that the timestampts are ordered.
        for (uint256 index = 0; index < segmentCount; ++index) {
            // Add the current segment amount to the sum.
            segmentAmountsSum += segments[index].amount;

            // Checks: the current timestampt is strictly greater than the previous timestampt.
            currentTimestamp = segments[index].timestampt;
            if (currentTimestamp <= previousTimestamp) {
                revert Errors.SablierV2LockupDynamic_SegmentTimestampsNotOrdered(
                    index, previousTimestamp, currentTimestamp
                );
            }

            // Make the current timestampt the previous timestampt of the next loop iteration.
            previousTimestamp = currentTimestamp;
        }

        // Checks: the deposit amount is equal to the segment amounts sum.
        if (depositAmount != segmentAmountsSum) {
            revert Errors.SablierV2LockupDynamic_DepositAmountNotEqualToSegmentAmountsSum(
                depositAmount, segmentAmountsSum
            );
        }

        return currentTimestamp;
    }
}
