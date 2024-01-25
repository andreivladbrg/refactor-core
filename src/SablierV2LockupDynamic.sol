// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.22;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ERC721 } from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import { PRBMathCastingUint128 as CastingUint128 } from "@prb/math/src/casting/Uint128.sol";
import { PRBMathCastingUint40 as CastingUint40 } from "@prb/math/src/casting/Uint40.sol";
import { SD59x18 } from "@prb/math/src/SD59x18.sol";
import { UD60x18 } from "@prb/math/src/UD60x18.sol";

import { SablierV2Lockup } from "./abstracts/SablierV2Lockup.sol";
import { ISablierV2Comptroller } from "./interfaces/ISablierV2Comptroller.sol";
import { ISablierV2LockupDynamic } from "./interfaces/ISablierV2LockupDynamic.sol";
import { ISablierV2NFTDescriptor } from "./interfaces/ISablierV2NFTDescriptor.sol";
import { Helpers } from "./libraries/Helpers.sol";
import { Lockup, LockupDynamic } from "./types/DataTypes.sol";

/*

███████╗ █████╗ ██████╗ ██╗     ██╗███████╗██████╗     ██╗   ██╗██████╗
██╔════╝██╔══██╗██╔══██╗██║     ██║██╔════╝██╔══██╗    ██║   ██║╚════██╗
███████╗███████║██████╔╝██║     ██║█████╗  ██████╔╝    ██║   ██║ █████╔╝
╚════██║██╔══██║██╔══██╗██║     ██║██╔══╝  ██╔══██╗    ╚██╗ ██╔╝██╔═══╝
███████║██║  ██║██████╔╝███████╗██║███████╗██║  ██║     ╚████╔╝ ███████╗
╚══════╝╚═╝  ╚═╝╚═════╝ ╚══════╝╚═╝╚══════╝╚═╝  ╚═╝      ╚═══╝  ╚══════╝

██╗      ██████╗  ██████╗██╗  ██╗██╗   ██╗██████╗     ██████╗ ██╗   ██╗███╗   ██╗ █████╗ ███╗   ███╗██╗ ██████╗
██║     ██╔═══██╗██╔════╝██║ ██╔╝██║   ██║██╔══██╗    ██╔══██╗╚██╗ ██╔╝████╗  ██║██╔══██╗████╗ ████║██║██╔════╝
██║     ██║   ██║██║     █████╔╝ ██║   ██║██████╔╝    ██║  ██║ ╚████╔╝ ██╔██╗ ██║███████║██╔████╔██║██║██║
██║     ██║   ██║██║     ██╔═██╗ ██║   ██║██╔═══╝     ██║  ██║  ╚██╔╝  ██║╚██╗██║██╔══██║██║╚██╔╝██║██║██║
███████╗╚██████╔╝╚██████╗██║  ██╗╚██████╔╝██║         ██████╔╝   ██║   ██║ ╚████║██║  ██║██║ ╚═╝ ██║██║╚██████╗
╚══════╝ ╚═════╝  ╚═════╝╚═╝  ╚═╝ ╚═════╝ ╚═╝         ╚═════╝    ╚═╝   ╚═╝  ╚═══╝╚═╝  ╚═╝╚═╝     ╚═╝╚═╝ ╚═════╝

*/

/// @title SablierV2LockupDynamic
/// @notice See the documentation in {ISablierV2LockupDynamic}.
contract SablierV2LockupDynamic is
    ISablierV2LockupDynamic, // 1 inherited component
    SablierV2Lockup // 14 inherited components
{
    using CastingUint128 for uint128;
    using CastingUint40 for uint40;
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////////////////
                                  PUBLIC CONSTANTS
    //////////////////////////////////////////////////////////////////////////*/

    /// @inheritdoc ISablierV2LockupDynamic
    uint256 public immutable override MAX_SEGMENT_COUNT;

    /// @dev Stream segments mapped by stream id.
    mapping(uint256 id => LockupDynamic.Segment[] segments) internal _segments;

    /*//////////////////////////////////////////////////////////////////////////
                                     CONSTRUCTOR
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Emits a {TransferAdmin} event.
    /// @param initialAdmin The address of the initial contract admin.
    /// @param initialComptroller The address of the initial comptroller.
    /// @param initialNFTDescriptor The address of the NFT descriptor contract.
    /// @param maxSegmentCount The maximum number of segments allowed in a stream.
    constructor(
        address initialAdmin,
        ISablierV2Comptroller initialComptroller,
        ISablierV2NFTDescriptor initialNFTDescriptor,
        uint256 maxSegmentCount
    )
        ERC721("Sablier V2 Lockup Dynamic NFT", "SAB-V2-LOCKUP-DYN")
        SablierV2Lockup(initialAdmin, initialComptroller, initialNFTDescriptor)
    {
        MAX_SEGMENT_COUNT = maxSegmentCount;
        nextStreamId = 1;
    }

    /*//////////////////////////////////////////////////////////////////////////
                           USER-FACING CONSTANT FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @inheritdoc ISablierV2LockupDynamic
    function getRange(uint256 streamId)
        external
        view
        override
        notNull(streamId)
        returns (LockupDynamic.Range memory range)
    {
        range = LockupDynamic.Range({ start: _streams[streamId].startTime, end: _streams[streamId].endTime });
    }

    /// @inheritdoc ISablierV2LockupDynamic
    function getSegments(uint256 streamId)
        external
        view
        override
        notNull(streamId)
        returns (LockupDynamic.Segment[] memory segments)
    {
        segments = _segments[streamId];
    }

    /// @inheritdoc ISablierV2LockupDynamic
    function getStream(uint256 streamId)
        external
        view
        override
        notNull(streamId)
        returns (Lockup.Stream memory stream)
    {
        stream = _streams[streamId];

        // Settled streams cannot be canceled.
        if (_statusOf(streamId) == Lockup.Status.SETTLED) {
            stream.isCancelable = false;
        }
    }

    /// @inheritdoc ISablierV2LockupDynamic
    function streamedAmountOf(uint256 streamId)
        public
        view
        override(SablierV2Lockup, ISablierV2LockupDynamic)
        returns (uint128)
    {
        return super.streamedAmountOf(streamId);
    }

    /*//////////////////////////////////////////////////////////////////////////
                         USER-FACING NON-CONSTANT FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @inheritdoc ISablierV2LockupDynamic
    function createWithDurations(LockupDynamic.CreateWithDurations calldata params)
        external
        override
        noDelegateCall
        returns (uint256 streamId)
    {
        // Checks: check the durations and generate the canonical segments.
        LockupDynamic.Segment[] memory segments = Helpers.checkDurationsAndCalculateTimestamps(params.segments);

        // Checks, Effects and Interactions: create the stream.
        streamId = _createWithTimestamps(
            LockupDynamic.CreateWithTimestamps({
                sender: params.sender,
                recipient: params.recipient,
                totalAmount: params.totalAmount,
                asset: params.asset,
                cancelable: params.cancelable,
                transferable: params.transferable,
                startTime: uint40(block.timestamp),
                segments: segments,
                broker: params.broker
            })
        );
    }

    /// @inheritdoc ISablierV2LockupDynamic
    function createWithTimestamps(LockupDynamic.CreateWithTimestamps calldata params)
        external
        override
        noDelegateCall
        returns (uint256 streamId)
    {
        // Checks, Effects and Interactions: create the stream.
        streamId = _createWithTimestamps(params);
    }

    /*//////////////////////////////////////////////////////////////////////////
                             INTERNAL CONSTANT FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Calculates the streamed amount without looking up the stream's status.
    function _calculateStreamedAmount(uint256 streamId) internal view override returns (uint128) {
        // If the start time is in the future, return zero.
        uint40 currentTime = uint40(block.timestamp);
        if (_streams[streamId].startTime >= currentTime) {
            return 0;
        }

        // If the end time is not in the future, return the deposited amount.
        uint40 endTime = _streams[streamId].endTime;
        if (endTime <= currentTime) {
            return _streams[streamId].amounts.deposited;
        }

        if (_segments[streamId].length > 1) {
            // If there is more than one segment, it may be necessary to iterate over all of them.
            return _calculateStreamedAmountForMultipleSegments(streamId);
        } else {
            // Otherwise, there is only one segment, and the calculation is simpler.
            return _calculateStreamedAmountForOneSegment(streamId);
        }
    }

    function _calculateStreamedAmountForCurrentSegment(
        uint256 streamId,
        uint256 index,
        uint128 previousSegmentAmounts
    )
        internal
        view
        returns (uint128)
    {
        uint40 currentTime = uint40(block.timestamp);

        // After exiting the loop, the current segment is at `index`.
        SD59x18 currentSegmentAmount = _segments[streamId][index].amount.intoSD59x18();
        SD59x18 currentSegmentExponent = _segments[streamId][index].exponent.intoSD59x18();
        uint40 currentSegmentTimestamp = _segments[streamId][index].timestampt;

        uint40 previousTimestamp;
        if (index > 0) {
            // When the current segment's index is greater than or equal to 1, it implies that the segment is not
            // the first. In this case, use the previous segment's timestampt.
            previousTimestamp = _segments[streamId][index - 1].timestampt;
        } else {
            // Otherwise, the current segment is the first, so use the start time as the previous timestampt.
            previousTimestamp = _streams[streamId].startTime;
        }

        // Calculate how much time has passed since the segment started, and the total time of the segment.
        SD59x18 elapsedSegmentTime = (currentTime - previousTimestamp).intoSD59x18();
        SD59x18 totalSegmentTime = (currentSegmentTimestamp - previousTimestamp).intoSD59x18();

        // Divide the elapsed segment time by the total duration of the segment.
        SD59x18 elapsedSegmentTimePercentage = elapsedSegmentTime.div(totalSegmentTime);

        // Calculate the streamed amount using the special formula.
        SD59x18 multiplier = elapsedSegmentTimePercentage.pow(currentSegmentExponent);
        SD59x18 segmentStreamedAmount = multiplier.mul(currentSegmentAmount);

        // Although the segment streamed amount should never exceed the total segment amount, this condition is
        // checked without asserting to avoid locking funds in case of a bug. If this situation occurs, the
        // amount streamed in the segment is considered zero (except for past withdrawals), and the segment is
        // effectively voided.
        if (segmentStreamedAmount.gt(currentSegmentAmount)) {
            return previousSegmentAmounts > _streams[streamId].amounts.withdrawn
                ? previousSegmentAmounts
                : _streams[streamId].amounts.withdrawn;
        }

        // Calculate the total streamed amount by adding the previous segment amounts and the amount streamed in
        // the current segment. Casting to uint128 is safe due to the if statement above.
        return previousSegmentAmounts + uint128(segmentStreamedAmount.intoUint256());
    }

    /// @dev Calculates the streamed amount for a stream with multiple segments.
    ///
    /// Notes:
    ///
    /// 1. Normalization to 18 decimals is not needed because there is no mix of amounts with different decimals.
    /// 2. The stream's start time must be in the past so that the calculations below do not overflow.
    /// 3. The stream's end time must be in the future so that the loop below does not panic with an "index out of
    /// bounds" error.
    function _calculateStreamedAmountForMultipleSegments(uint256 streamId) internal view returns (uint128) {
        unchecked {
            uint40 currentTime = uint40(block.timestamp);
            LockupDynamic.Segment[] memory segments = _segments[streamId];

            // Sum the amounts in all segments that precede the current time.
            uint128 previousSegmentAmounts;
            uint40 currentSegmentTimestamp = segments[0].timestampt;
            uint256 index = 0;
            while (currentSegmentTimestamp < currentTime) {
                previousSegmentAmounts += segments[index].amount;
                index += 1;
                currentSegmentTimestamp = segments[index].timestampt;
            }

            // Calculate the streamed amount for the current segment.
            return _calculateStreamedAmountForCurrentSegment(streamId, index, previousSegmentAmounts);
        }
    }

    /// @dev Calculates the streamed amount for a a stream with one segment. Normalization to 18 decimals is not
    /// needed because there is no mix of amounts with different decimals.
    function _calculateStreamedAmountForOneSegment(uint256 streamId) internal view returns (uint128) {
        unchecked {
            // Calculate how much time has passed since the stream started, and the stream's total duration.
            SD59x18 elapsedTime = (uint40(block.timestamp) - _streams[streamId].startTime).intoSD59x18();
            SD59x18 totalTime = (_streams[streamId].endTime - _streams[streamId].startTime).intoSD59x18();

            // Divide the elapsed time by the stream's total duration.
            SD59x18 elapsedTimePercentage = elapsedTime.div(totalTime);

            // Cast the stream parameters to SD59x18.
            SD59x18 exponent = _segments[streamId][0].exponent.intoSD59x18();
            SD59x18 depositedAmount = _streams[streamId].amounts.deposited.intoSD59x18();

            // Calculate the streamed amount using the special formula.
            SD59x18 multiplier = elapsedTimePercentage.pow(exponent);
            SD59x18 streamedAmount = multiplier.mul(depositedAmount);

            // Although the streamed amount should never exceed the deposited amount, this condition is checked
            // without asserting to avoid locking funds in case of a bug. If this situation occurs, the withdrawn
            // amount is considered to be the streamed amount, and the stream is effectively frozen.
            if (streamedAmount.gt(depositedAmount)) {
                return _streams[streamId].amounts.withdrawn;
            }

            // Cast the streamed amount to uint128. This is safe due to the check above.
            return uint128(streamedAmount.intoUint256());
        }
    }

    /*//////////////////////////////////////////////////////////////////////////
                           INTERNAL NON-CONSTANT FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev See the documentation for the user-facing functions that call this internal function.
    function _createWithTimestamps(LockupDynamic.CreateWithTimestamps memory params)
        internal
        returns (uint256 streamId)
    {
        // Safe Interactions: query the protocol fee. This is safe because it's a known Sablier contract that does
        // not call other unknown contracts.
        UD60x18 protocolFee = comptroller.protocolFees(params.asset);

        // Checks: check the fees and calculate the fee amounts.
        Lockup.CreateAmounts memory createAmounts =
            Helpers.checkAndCalculateFees(params.totalAmount, protocolFee, params.broker.fee, MAX_FEE);

        uint40 endTime =
            Helpers.checkSegments(params.segments, createAmounts.deposit, params.startTime, MAX_SEGMENT_COUNT);

        streamId = _create(
            Lockup.CreateParams({
                sender: params.sender,
                recipient: params.recipient,
                createAmounts: createAmounts,
                asset: params.asset,
                cancelable: params.cancelable,
                transferable: params.transferable,
                startTime: params.startTime,
                endTime: endTime,
                broker: params.broker
            })
        );

        uint256 segmentCount = params.segments.length;

        // Effects: store the segments. Since Solidity lacks a syntax for copying arrays directly from
        // memory to storage, a manual approach is necessary. See
        // https://github.com/ethereum/solidity/issues/12783.
        for (uint256 i = 0; i < segmentCount; ++i) {
            _segments[streamId].push(params.segments[i]);
        }

        // Log the newly created stream.
        emit ISablierV2LockupDynamic.CreateLockupDynamicStream({
            streamId: streamId,
            funder: msg.sender,
            sender: params.sender,
            recipient: params.recipient,
            amounts: createAmounts,
            asset: params.asset,
            cancelable: params.cancelable,
            transferable: params.transferable,
            segments: params.segments,
            startTime: params.startTime,
            broker: params.broker.account
        });
    }
}
