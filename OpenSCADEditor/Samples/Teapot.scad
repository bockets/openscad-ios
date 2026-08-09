// Teapot
//
// A smooth, rounded model — unlike a box, its curved surfaces catch the
// preview's lighting and ambient occlusion, so shading and depth actually read.

/* [Size] */
body_diameter = 60;   // [30:100]
body_squish = 0.8;    // [0.55:0.05:1]

/* [Features] */
show_lid = true;
show_spout = true;
show_handle = true;

/* [Quality] */
resolution = 48;      // [24:8:96]

$fn = resolution;

body_r = body_diameter / 2;
top_z = body_r * body_squish;

module body() {
    scale([1, 1, body_squish]) sphere(r = body_r);
}

module lid() {
    lid_r = body_r * 0.55;
    // shallow dome resting on top of the body
    translate([0, 0, top_z * 0.72])
        scale([1, 1, 0.55]) sphere(r = lid_r);
    // knob
    translate([0, 0, top_z * 0.72 + lid_r * 0.45])
        sphere(r = body_r * 0.12);
}

// A sphere placed along the spout's rising arc; radius tapers toward the tip.
module spout_ball(t) {
    x = body_r * (0.65 + 1.05 * t);
    z = -body_r * 0.15 + body_r * 1.05 * pow(t, 1.4);
    r = body_r * (0.22 * (1 - t) + 0.045);
    translate([x, 0, z]) sphere(r = r, $fn = 24);
}

module spout() {
    steps = 12;
    for (i = [0 : steps - 1])
        hull() { spout_ball(i / steps); spout_ball((i + 1) / steps); }
}

// A sphere on the C-shaped handle arc, in the X-Z plane on the far side.
module handle_ball(t) {
    ang = -120 + 240 * t;
    arc_r = body_r * 0.62;
    cx = -body_r * 0.78;
    cz = body_r * 0.05;
    translate([cx - arc_r * cos(ang), 0, cz + arc_r * sin(ang)])
        sphere(r = body_r * 0.085, $fn = 24);
}

module handle() {
    steps = 16;
    for (i = [0 : steps - 1])
        hull() { handle_ball(i / steps); handle_ball((i + 1) / steps); }
}

module teapot() {
    body();
    if (show_lid) lid();
    if (show_spout) spout();
    if (show_handle) handle();
}

teapot();
