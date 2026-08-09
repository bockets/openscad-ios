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
            load("ParametricBox", fallback: Embedded.parametricBox),
            load("PhoneStand", fallback: Embedded.phoneStand)
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

        static let phoneStand = """
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
        """
    }
}
