// Teapot
//
// A smooth, rounded model — its curved surfaces catch the preview's lighting
// and ambient occlusion, so shading and depth read (unlike a flat box).
//
// Built from a few solids of revolution (rotate_extrude) rather than a stack of
// hulled spheres, so OpenSCAD performs only a handful of boolean unions to make
// the STL and it renders quickly.

/* [Size] */
body_diameter = 60;   // [30:100]
body_squish = 0.85;   // [0.6:0.05:1.1]

/* [Features] */
show_lid = true;
show_spout = true;
show_handle = true;

/* [Quality] */
resolution = 64;      // [24:8:120]

$fn = resolution;

r = body_diameter / 2;
h = body_diameter * body_squish;

wall  = r * 0.12;   // shell/floor thickness
mouth = r * 0.42;   // radius of the top opening the lid covers

// Belly of the pot: an outer solid of revolution with an inner cavity carved
// out and the top opened, so it's a hollow pot the lid seats onto.
module body() {
    difference() {
        rotate_extrude()
            polygon([
                [0,        0],
                [r * 0.40, 0],
                [r * 0.98, h * 0.20],
                [r * 1.00, h * 0.44],
                [r * 0.82, h * 0.68],
                [r * 0.55, h * 0.82],
                [0,        h * 0.82]
            ]);
        // Inner cavity: follows the wall up and past the rim within `mouth`,
        // leaving a `wall`-thick floor and an annular rim lip for the lid.
        rotate_extrude()
            polygon([
                [0,          wall],
                [r * 0.30,   wall],
                [r * 0.86,   h * 0.22],
                [r * 0.88,   h * 0.44],
                [r * 0.70,   h * 0.66],
                [mouth,      h * 0.82],
                [mouth,      h * 0.98],
                [0,          h * 0.98]
            ]);
    }
}

// Domed lid with a knob, also one revolve.
module lid() {
    translate([0, 0, h * 0.80])
        rotate_extrude()
            polygon([
                [0,        0],
                [r * 0.56, 0],
                [r * 0.46, h * 0.07],
                [r * 0.13, h * 0.11],
                [r * 0.13, h * 0.17],
                [r * 0.06, h * 0.22],
                [0,        h * 0.22]
            ]);
}

// Tapered spout: a single cone tilted up and out of the belly.
module spout() {
    translate([r * 0.55, 0, h * 0.32])
        rotate([0, 52, 0])
            cylinder(h = body_diameter * 0.85, r1 = r * 0.24, r2 = r * 0.07);
}

// C-shaped handle: a partial torus stood up in the side plane, its opening
// turned to face the pot so both ends embed into the belly.
module handle() {
    translate([-r * 0.78, 0, h * 0.50])
        rotate([90, 0, 0])
            rotate([0, 0, 65])
                rotate_extrude(angle = 230)
                    translate([r * 0.50, 0])
                        circle(r = r * 0.085, $fn = 28);
}

module teapot() {
    body();
    if (show_lid) lid();
    if (show_spout) spout();
    if (show_handle) handle();
}

teapot();
