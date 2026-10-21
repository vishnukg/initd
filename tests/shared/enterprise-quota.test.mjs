import { test } from 'node:test';
import assert from 'node:assert/strict';
import { agyValue, claudeValue } from '../../shared/configs/tmux/.config/tmux/status-renderer.mjs';

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

const at = seconds => new Date(seconds * 1000).toISOString();
for (const { name, model = 'Gemini 3.8 Flash', quota, now = 0, expected } of [
    { name: 'five-hour window from the remaining fraction', expected: 'Gemini 3.8 Flash · 75% · 1h0m', quota: {
        'gemini-5h': { remaining_fraction: 0.25, reset_time: at(3600) },
        'gemini-weekly': { remaining_fraction: 0.9, reset_time: at(90000) },
    } },
    { name: 'a fuller weekly window past 50 percent takes the slot', expected: 'Gemini 3.8 Flash · 80% week · 1d1h', quota: {
        'gemini-5h': { remaining_fraction: 0.7, reset_time: at(3600) },
        'gemini-weekly': { remaining_fraction: 0.2, reset_time: at(90000) },
    } },
    { name: 'a third-party model reads the 3p windows', model: 'Claude Opus 5', expected: 'Claude Opus 5 · 40% · 1h0m', quota: {
        'gemini-5h': { remaining_fraction: 0, reset_time: at(3600) },
        '3p-5h': { remaining_fraction: 0.6, reset_time: at(3600) },
    } },
    { name: 'an expired reset leaves only the model', now: 3600, expected: 'Gemini 3.8 Flash', quota: {
        'gemini-5h': { remaining_fraction: 0.25, reset_time: at(3600) },
    } },
    { name: 'a malformed fraction or reset time is ignored', expected: 'Gemini 3.8 Flash', quota: {
        'gemini-5h': { remaining_fraction: 1.5, reset_time: at(3600) },
        'gemini-weekly': { remaining_fraction: 0.1, reset_time: 'soon' },
    } },
    { name: 'no quota at all', expected: 'Gemini 3.8 Flash', quota: undefined },
]) {
    test(`agy quota: ${name}`, () => {
        // Arrange
        const data = { model: { id: model, display_name: model }, quota };

        // Act
        const rendered = agyValue(data, now);

        // Assert
        assert.equal(rendered, expected);
    });
}
