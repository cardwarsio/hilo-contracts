// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

library CEILib {
    error InvalidCEIOrder();

    enum CEIStage {
        Checks,
        Effects,
        Interactions
    }

    struct CEIContext {
        CEIStage stage;
        bool checksComplete;
        bool effectsComplete;
    }

    function init(CEIContext storage ctx) internal {
        ctx.stage = CEIStage.Checks;
        ctx.checksComplete = false;
        ctx.effectsComplete = false;
    }

    function init(CEIContext memory ctx) internal pure {
        ctx.stage = CEIStage.Checks;
        ctx.checksComplete = false;
        ctx.effectsComplete = false;
    }

    function completeChecks(CEIContext storage ctx) internal {
        if (ctx.stage != CEIStage.Checks) {
            revert InvalidCEIOrder();
        }
        ctx.checksComplete = true;
        ctx.stage = CEIStage.Effects;
    }

    function completeChecks(CEIContext memory ctx) internal pure {
        if (ctx.stage != CEIStage.Checks) {
            revert InvalidCEIOrder();
        }
        ctx.checksComplete = true;
        ctx.stage = CEIStage.Effects;
    }

    function completeEffects(CEIContext storage ctx) internal {
        if (ctx.stage != CEIStage.Effects || !ctx.checksComplete) {
            revert InvalidCEIOrder();
        }
        ctx.effectsComplete = true;
        ctx.stage = CEIStage.Interactions;
    }

    function completeEffects(CEIContext memory ctx) internal pure {
        if (ctx.stage != CEIStage.Effects || !ctx.checksComplete) {
            revert InvalidCEIOrder();
        }
        ctx.effectsComplete = true;
        ctx.stage = CEIStage.Interactions;
    }

    function requireChecks(CEIContext storage ctx) internal view {
        if (ctx.stage != CEIStage.Checks || ctx.checksComplete) {
            revert InvalidCEIOrder();
        }
    }

    function requireChecks(CEIContext memory ctx) internal pure {
        if (ctx.stage != CEIStage.Checks || ctx.checksComplete) {
            revert InvalidCEIOrder();
        }
    }

    function requireEffects(CEIContext storage ctx) internal view {
        if (ctx.stage != CEIStage.Effects || !ctx.checksComplete || ctx.effectsComplete) {
            revert InvalidCEIOrder();
        }
    }

    function requireEffects(CEIContext memory ctx) internal pure {
        if (ctx.stage != CEIStage.Effects || !ctx.checksComplete || ctx.effectsComplete) {
            revert InvalidCEIOrder();
        }
    }

    function requireInteractions(CEIContext storage ctx) internal view {
        if (ctx.stage != CEIStage.Interactions || !ctx.effectsComplete) {
            revert InvalidCEIOrder();
        }
    }

    function requireInteractions(CEIContext memory ctx) internal pure {
        if (ctx.stage != CEIStage.Interactions || !ctx.effectsComplete) {
            revert InvalidCEIOrder();
        }
    }
}

