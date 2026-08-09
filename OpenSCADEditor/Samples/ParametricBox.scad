// Parametric Box

/* [Size] */
width = 40;       // [10:100]
depth = 30;       // [10:100]
height = 25;      // [5:0.5:60]

/* [Walls] */
wall = 2;         // [1:0.5:5]
has_lid = true;
rounding = 3;     // [0:10]

/* [Style] */
corner_style = "round"; // [round, sharp, chamfer]
sides = 6;              // [3, 4, 5, 6, 8]

module box() {
    difference() {
        cube([width, depth, height], center = true);
        translate([0, 0, wall])
            cube([width - 2 * wall, depth - 2 * wall, height], center = true);
    }
}

box();
