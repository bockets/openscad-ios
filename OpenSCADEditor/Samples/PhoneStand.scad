// Phone Stand

/* [Dimensions] */
width = 80;        // [50:120]
thickness = 10;    // [4:20]
angle = 65;        // [30:85]

/* [Options] */
cable_slot = true;
slot_width = 20;   // [10:40]

module stand() {
    rotate([angle, 0, 0])
        cube([width, thickness, 100]);
}

stand();
