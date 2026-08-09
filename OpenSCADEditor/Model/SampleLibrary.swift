import Foundation

/// A named `.scad` document available from the Samples menu.
struct ScadSample: Equatable {
    let name: String
    let source: String
}

/// Provides the bundled sample `.scad` files, falling back to embedded source
/// if the resource can't be located in the app bundle.
enum SampleLibrary {

    static var all: [ScadSample] {
        [
            load("Teapot", fallback: Embedded.teapot),
            load("ParametricBox", fallback: Embedded.parametricBox)
        ]
    }

    static var `default`: ScadSample { all[0] }

    private static func load(_ resource: String, fallback: String) -> ScadSample {
        if let url = Bundle.main.url(forResource: resource, withExtension: "scad"),
           let source = try? String(contentsOf: url, encoding: .utf8) {
            return ScadSample(name: displayName(resource), source: source)
        }
        return ScadSample(name: displayName(resource), source: fallback)
    }

    /// "ParametricBox" -> "Parametric Box"
    private static func displayName(_ resource: String) -> String {
        var result = ""
        for (index, character) in resource.enumerated() {
            if index > 0, character.isUppercase { result.append(" ") }
            result.append(character)
        }
        return result
    }

    private enum Embedded {
        static let teapot = """
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
            translate([0, 0, top_z * 0.72])
                scale([1, 1, 0.55]) sphere(r = lid_r);
            translate([0, 0, top_z * 0.72 + lid_r * 0.45])
                sphere(r = body_r * 0.12);
        }

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
        """

        static let parametricBox = """
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
        """
    }
}
