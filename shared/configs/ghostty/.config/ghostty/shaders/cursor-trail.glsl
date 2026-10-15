// Cursor trail, Ghostty's stand-in for kitty's cursor_trail (kitty.conf): when
// the cursor jumps, the block sweeps from where it was to where it is and the
// tail catches up with the head, so the eye follows the move instead of hunting
// for where the cursor landed.
//
// Pixel coordinates throughout, y up (fragCoord's convention). Ghostty hands the
// cursor as its -X,+Y corner, i.e. top-left, plus width and height.

const float DURATION = 0.12; // seconds for the tail to reach the head
const float MIN_CELLS = 2.0; // shorter moves (typing) get no trail, as kitty's
                             // cursor_trail_start_threshold 2
const float OPACITY = 0.7;   // at the head, fading to 0 at the tail

float easeOutCubic(float x) {
    return 1.0 - pow(1.0 - x, 3.0);
}

// The [lo, hi] range of t at which a box centred at a + t*d, half-size h along
// this axis, covers p. Empty when lo > hi. With d == 0 it is all or nothing.
vec2 coverage(float p, float a, float d, float h) {
    if (abs(d) < 1e-4) {
        return abs(p - a) <= h ? vec2(-1e9, 1e9) : vec2(1.0, 0.0);
    }
    float t0 = (p - h - a) / d;
    float t1 = (p + h - a) / d;
    return vec2(min(t0, t1), max(t0, t1));
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    fragColor = texture(iChannel0, fragCoord / iResolution.xy);

    vec2 size = iCurrentCursor.zw;
    if (size.x <= 0.0 || size.y <= 0.0 || iFocus == 0) return;

    vec2 half_ = size * 0.5;
    vec2 head = iCurrentCursor.xy + vec2(half_.x, -half_.y);
    vec2 tail = iPreviousCursor.xy + vec2(iPreviousCursor.z * 0.5, -iPreviousCursor.w * 0.5);
    vec2 d = head - tail;
    if (length(d / size) < MIN_CELLS) return;

    float progress = (iTime - iTimeCursorChange) / DURATION;
    if (progress >= 1.0) return;

    // The swept box is exact (no sampling gaps on long jumps): p is inside it
    // when the per-axis ranges of t overlap. The tail end recedes toward the
    // head as the animation runs.
    vec2 cx = coverage(fragCoord.x, tail.x, d.x, half_.x);
    vec2 cy = coverage(fragCoord.y, tail.y, d.y, half_.y);
    float lo = max(max(cx.x, cy.x), easeOutCubic(progress));
    float hi = min(min(cx.y, cy.y), 1.0);
    if (lo > hi) return;

    // Brightest nearest the head; the cursor itself is already drawn.
    float alpha = OPACITY * hi * (1.0 - progress);
    fragColor = mix(fragColor, vec4(iCurrentCursorColor.rgb, 1.0), alpha);
}
