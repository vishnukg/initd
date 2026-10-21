import { test } from 'node:test';
import assert from 'node:assert/strict';
import { claudeValue } from '../../shared/configs/tmux/.config/tmux/status-renderer.mjs';

for (const { name, rateLimits, now, expected } of [
    { name: 'enterprise budget includes overage', now: 0, expected: 'Sonnet · 125% budget · 1d1h', rateLimits: {
        spend_limit: { used_percentage: 125, resets_at: 90000 },
        five_hour: { used_percentage: 30, resets_at: 3600 },
    } },
    { name: 'subscription keeps its existing format', now: 0, expected: 'Sonnet · 30% · 1h0m', rateLimits: {
        five_hour: { used_percentage: 30, resets_at: 3600 },
    } },
    { name: 'expired quota leaves only the model', now: 3600, expected: 'Sonnet', rateLimits: {
        five_hour: { used_percentage: 30, resets_at: 3600 },
    } },
    { name: 'weekly escalation includes the 50 percent boundary', now: 3600, expected: 'Sonnet · 50% week · 1d0h', rateLimits: {
        five_hour: { used_percentage: 30, resets_at: 3600 },
        seven_day: { used_percentage: 50, resets_at: 90000 },
    } },
]) {
    test(`Claude quota: ${name}`, () => {
        // Arrange
        const data = { model: { display_name: 'Sonnet' }, rate_limits: rateLimits };

        // Act
        const rendered = claudeValue(data, now);

        // Assert
        assert.equal(rendered, expected);
    });
}
