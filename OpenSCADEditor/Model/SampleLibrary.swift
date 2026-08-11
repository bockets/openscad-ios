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
            load("Teapot", fallback: Embedded.teapot)
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
        // A smooth, rounded model — its curved surfaces catch the preview's lighting
        // and ambient occlusion, so shading and depth read (unlike a flat box).
        //
        // Built from a few solids of revolution (rotate_extrude) rather than a stack
        // of hulled spheres, so OpenSCAD performs only a handful of boolean unions to
        // make the STL and it renders quickly.

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

        module body() {
            difference() {
                // Outer shell: a solid of revolution from base to rim.
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
                // Hollow the inside and open the top: subtract an inner solid that
                // follows the wall up and past the rim within `mouth`, leaving a
                // `wall`-thick floor and an annular rim lip for the lid to rest on.
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

        module spout() {
            translate([r * 0.55, 0, h * 0.32])
                rotate([0, 52, 0])
                    cylinder(h = body_diameter * 0.85, r1 = r * 0.24, r2 = r * 0.07);
        }

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
        """
    }
}
