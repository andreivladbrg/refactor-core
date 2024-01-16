// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.22;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ERC721 } from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import { UD60x18, ud } from "@prb/math/src/UD60x18.sol";

import { SablierV2Lockup } from "./abstracts/SablierV2Lockup.sol";
import { SablierV2Lockup } from "./abstracts/SablierV2Lockup.sol";
import { ISablierV2Comptroller } from "./interfaces/ISablierV2Comptroller.sol";
import { ISablierV2LockupLinear } from "./interfaces/ISablierV2LockupLinear.sol";
import { ISablierV2NFTDescriptor } from "./interfaces/ISablierV2NFTDescriptor.sol";
import { Errors } from "./libraries/Errors.sol";
import { Helpers } from "./libraries/Helpers.sol";
import { Lockup, LockupLinear } from "./types/DataTypes.sol";

/*

███████╗ █████╗ ██████╗ ██╗     ██╗███████╗██████╗     ██╗   ██╗██████╗
██╔════╝██╔══██╗██╔══██╗██║     ██║██╔════╝██╔══██╗    ██║   ██║╚════██╗
███████╗███████║██████╔╝██║     ██║█████╗  ██████╔╝    ██║   ██║ █████╔╝
╚════██║██╔══██║██╔══██╗██║     ██║██╔══╝  ██╔══██╗    ╚██╗ ██╔╝██╔═══╝
███████║██║  ██║██████╔╝███████╗██║███████╗██║  ██║     ╚████╔╝ ███████╗
╚══════╝╚═╝  ╚═╝╚═════╝ ╚══════╝╚═╝╚══════╝╚═╝  ╚═╝      ╚═══╝  ╚══════╝

██╗      ██████╗  ██████╗██╗  ██╗██╗   ██╗██████╗     ██╗     ██╗███╗   ██╗███████╗ █████╗ ██████╗
██║     ██╔═══██╗██╔════╝██║ ██╔╝██║   ██║██╔══██╗    ██║     ██║████╗  ██║██╔════╝██╔══██╗██╔══██╗
██║     ██║   ██║██║     █████╔╝ ██║   ██║██████╔╝    ██║     ██║██╔██╗ ██║█████╗  ███████║██████╔╝
██║     ██║   ██║██║     ██╔═██╗ ██║   ██║██╔═══╝     ██║     ██║██║╚██╗██║██╔══╝  ██╔══██║██╔══██╗
███████╗╚██████╔╝╚██████╗██║  ██╗╚██████╔╝██║         ███████╗██║██║ ╚████║███████╗██║  ██║██║  ██║
╚══════╝ ╚═════╝  ╚═════╝╚═╝  ╚═╝ ╚═════╝ ╚═╝         ╚══════╝╚═╝╚═╝  ╚═══╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝

*/

/// @title SablierV2LockupLinear
/// @notice See the documentation in {ISablierV2LockupLinear}.
contract SablierV2LockupLinear is
    ISablierV2LockupLinear, // 5 inherited components
    SablierV2Lockup // 14 inherited components
{
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////////////////
                                  PRIVATE STORAGE
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Cliff times mapped by stream id.
    mapping(uint256 id => uint40 cliff) internal _cliffs;

    /*//////////////////////////////////////////////////////////////////////////
                                     CONSTRUCTOR
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Emits a {TransferAdmin} event.
    /// @param initialAdmin The address of the initial contract admin.
    /// @param initialComptroller The address of the initial comptroller.
    /// @param initialNFTDescriptor The address of the initial NFT descriptor.
    constructor(
        address initialAdmin,
        ISablierV2Comptroller initialComptroller,
        ISablierV2NFTDescriptor initialNFTDescriptor
    )
        ERC721("Sablier V2 Lockup Linear NFT", "SAB-V2-LOCKUP-LIN")
        SablierV2Lockup(initialAdmin, initialComptroller, initialNFTDescriptor)
    {
        nextStreamId = 1;
    }

    /*//////////////////////////////////////////////////////////////////////////
                           USER-FACING CONSTANT FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @inheritdoc ISablierV2LockupLinear
    function getCliffTime(uint256 streamId) external view override notNull(streamId) returns (uint40 cliffTime) {
        cliffTime = _cliffs[streamId];
    }

    /// @inheritdoc ISablierV2LockupLinear
    function getRange(uint256 streamId)
        external
        view
        override
        notNull(streamId)
        returns (LockupLinear.Range memory range)
    {
        range = LockupLinear.Range({
            start: _streams[streamId].startTime,
            cliff: _cliffs[streamId],
            end: _streams[streamId].endTime
        });
    }

    /// @inheritdoc ISablierV2LockupLinear
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

    function streamedAmountOf(uint256 streamId)
        public
        view
        override(SablierV2Lockup, ISablierV2LockupLinear)
        returns (uint128)
    {
        return super.streamedAmountOf(streamId);
    }

    /*//////////////////////////////////////////////////////////////////////////
                         USER-FACING NON-CONSTANT FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @inheritdoc ISablierV2LockupLinear
    function createWithDurations(LockupLinear.CreateWithDurations calldata params)
        external
        override
        noDelegateCall
        returns (uint256 streamId)
    {
        // Set the current block timestamp as the stream's start time.
        LockupLinear.Range memory range;
        range.start = uint40(block.timestamp);

        // Calculate the cliff time and the end time. It is safe to use unchecked arithmetic because
        // {_createWithRange} will nonetheless check that the end time is greater than the cliff time,
        // and also that the cliff time is greater than or equal to the start time.
        unchecked {
            range.cliff = range.start + params.durations.cliff;
            range.end = range.start + params.durations.total;
        }
        // Checks, Effects and Interactions: create the stream.
        streamId = _createWithRange(
            LockupLinear.CreateWithRange({
                sender: params.sender,
                recipient: params.recipient,
                totalAmount: params.totalAmount,
                asset: params.asset,
                cancelable: params.cancelable,
                transferable: params.transferable,
                range: range,
                broker: params.broker
            })
        );
    }

    /// @inheritdoc ISablierV2LockupLinear
    function createWithRange(LockupLinear.CreateWithRange calldata params)
        external
        override
        noDelegateCall
        returns (uint256 streamId)
    {
        // Checks, Effects and Interactions: create the stream.
        streamId = _createWithRange(params);
    }

    /*//////////////////////////////////////////////////////////////////////////
                           INTERNAL CONSTANT FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Calculates the streamed amount without looking up the stream's status.
    function _calculateStreamedAmount(uint256 streamId) internal view override returns (uint128) {
        // If the cliff time is in the future, return zero.
        uint256 cliffTime = uint256(_cliffs[streamId]);
        uint256 currentTime = block.timestamp;
        if (cliffTime > currentTime) {
            return 0;
        }

        // If the end time is not in the future, return the deposited amount.
        uint256 endTime = uint256(_streams[streamId].endTime);
        if (currentTime >= endTime) {
            return _streams[streamId].amounts.deposited;
        }

        // In all other cases, calculate the amount streamed so far. Normalization to 18 decimals is not needed
        // because there is no mix of amounts with different decimals.
        unchecked {
            // Calculate how much time has passed since the stream started, and the stream's total duration.
            uint256 startTime = uint256(_streams[streamId].startTime);
            UD60x18 elapsedTime = ud(currentTime - startTime);
            UD60x18 totalTime = ud(endTime - startTime);

            // Divide the elapsed time by the stream's total duration.
            UD60x18 elapsedTimePercentage = elapsedTime.div(totalTime);

            // Cast the deposited amount to UD60x18.
            UD60x18 depositedAmount = ud(_streams[streamId].amounts.deposited);

            // Calculate the streamed amount by multiplying the elapsed time percentage by the deposited amount.
            UD60x18 streamedAmount = elapsedTimePercentage.mul(depositedAmount);

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

    function _createWithRange(LockupLinear.CreateWithRange memory params) internal returns (uint256 streamId) {
        // Checks: the start time is less than or equal to the cliff time.
        if (params.range.start > params.range.cliff) {
            revert Errors.SablierV2LockupLinear_StartTimeGreaterThanCliffTime(params.range.start, params.range.cliff);
        }

        // Checks: the cliff time is strictly less than the end time.
        if (params.range.cliff >= params.range.end) {
            revert Errors.SablierV2LockupLinear_CliffTimeNotLessThanEndTime(params.range.cliff, params.range.end);
        }

        // Safe Interactions: query the protocol fee. This is safe because it's a known Sablier contract that does
        // not call other unknown contracts.
        UD60x18 protocolFee = comptroller.protocolFees(params.asset);

        // Checks: check the fees and calculate the fee amounts.
        Lockup.CreateAmounts memory createAmounts =
            Helpers.checkAndCalculateFees(params.totalAmount, protocolFee, params.broker.fee, MAX_FEE);

        streamId = _create(
            Lockup.CreateParams({
                sender: params.sender,
                recipient: params.recipient,
                createAmounts: createAmounts,
                asset: params.asset,
                cancelable: params.cancelable,
                transferable: params.transferable,
                startTime: params.range.start,
                endTime: params.range.end,
                broker: params.broker
            })
        );

        _cliffs[streamId] = params.range.cliff;

        // Log the newly created stream.
        emit ISablierV2LockupLinear.CreateLockupLinearStream({
            streamId: streamId,
            funder: msg.sender,
            sender: params.sender,
            recipient: params.recipient,
            amounts: createAmounts,
            asset: params.asset,
            cancelable: params.cancelable,
            transferable: params.transferable,
            range: params.range,
            broker: params.broker.account
        });
    }
}
